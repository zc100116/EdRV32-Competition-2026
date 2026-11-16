#!/usr/bin/env python3
"""train_masked.py: card 86 supplement 2, pose training with ignored instance classes.
Class 14 is a data-only flag. The saved native YOLOv8n-pose model has 14 classes.
Detection-loss mechanics derive from Ultralytics 8.4.160 (AGPL-3.0).
Clock domain: not applicable (GPU training).
"""
import argparse
from datetime import datetime, timezone
from itertools import repeat
import json
import math
from pathlib import Path
import torch
from ultralytics import YOLO
from ultralytics.data.dataset import YOLODataset
from ultralytics.data.utils import verify_image_label
from ultralytics.models.yolo.pose.train import PoseTrainer
from ultralytics.nn.tasks import PoseModel
from ultralytics.utils import colorstr
from ultralytics.utils.loss import v8PoseLoss
from ultralytics.utils.tal import TaskAlignedAssigner, make_anchors
from ultralytics.utils.torch_utils import unwrap_model

IGNORE_CLASS = 14
SELF_CHECK = False


class MaskedDataset(YOLODataset):
    def verify_args(self):
        nkpt, ndim = self.data['kpt_shape']
        return verify_image_label, zip(
            self.im_files, self.label_files, repeat(self.prefix), repeat(True),
            repeat(IGNORE_CLASS + 1), repeat(nkpt), repeat(ndim), repeat(False))


class MaskedAssigner(TaskAlignedAssigner):
    def get_box_metrics(self, scores, boxes, labels, gt_boxes, mask_gt):
        indices = mask_gt.bool().nonzero(as_tuple=True)
        classes = labels[indices[0], indices[1], 0].long()
        known_scores = scores[indices[0], indices[2], classes.clamp(max=13)]
        maximum_scores = scores.amax(-1)[indices[0], indices[2]]
        chosen = torch.where(classes == IGNORE_CLASS, maximum_scores, known_scores)
        ious = self.iou_calculation(gt_boxes[indices[:2]], boxes[indices[0], indices[2]])
        alignment = chosen.pow(self.alpha) * ious.pow(self.beta)
        shape = self.bs, self.n_max_boxes, boxes.shape[-2]
        overlaps = torch.zeros(shape, dtype=boxes.dtype, device=boxes.device)
        metrics = torch.zeros(shape, dtype=alignment.dtype, device=scores.device)
        overlaps[indices] = ious
        metrics[indices] = alignment
        return metrics, overlaps

    def get_targets(self, labels, boxes, target_indices, foreground):
        # The temporary one-hot channel carries box/DFL weights, not a class target.
        mapped = torch.where(labels == IGNORE_CLASS, 0, labels)
        target_labels, target_boxes, weights = super().get_targets(
            mapped, boxes, target_indices, foreground)
        assigned = labels.squeeze(-1).gather(1, target_indices.long())
        target_labels = torch.where(assigned == IGNORE_CLASS, IGNORE_CLASS, target_labels)
        return target_labels, target_boxes, weights


class MaskedPoseLoss(v8PoseLoss):
    def __init__(self, model):
        super().__init__(model)
        current = self.assigner
        self.assigner = MaskedAssigner(
            topk=current.topk, num_classes=14, alpha=current.alpha, beta=current.beta,
            stride=current.stride, topk2=current.topk2)
        self.audit = dict(ignored_anchors=0, known_anchors=0, ignored_target_sum=0,
                          ignored_cls_loss=0, known_cls_loss=0)

    def get_assigned_targets_and_loss(self, preds, batch):
        loss = torch.zeros(3, device=self.device)
        distribution = preds['boxes'].permute(0, 2, 1).contiguous()
        scores = preds['scores'].permute(0, 2, 1).contiguous()
        anchors, strides = make_anchors(preds['feats'], self.stride, 0.5)
        dtype = scores.dtype
        batch_size = scores.shape[0]
        image_size = torch.tensor(preds['feats'][0].shape[2:], device=self.device,
                                  dtype=dtype) * self.stride[0]
        targets = torch.cat((batch['batch_idx'].view(-1, 1), batch['cls'].view(-1, 1),
                             batch['bboxes']), 1)
        targets = self.preprocess(targets.to(self.device), batch_size,
                                  scale_tensor=image_size[[1, 0, 1, 0]])
        labels, boxes = targets.split((1, 4), 2)
        mask_gt = boxes.sum(2, keepdim=True).gt_(0.0)
        predicted_boxes = self.bbox_decode(anchors, distribution)
        assigned_labels, assigned_boxes, weights, foreground, target_indices = self.assigner(
            scores.detach().sigmoid(), (predicted_boxes.detach() * strides).type(boxes.dtype),
            anchors * strides, labels, boxes, mask_gt)
        ignored = (assigned_labels == IGNORE_CLASS) & foreground
        classification_targets = weights.masked_fill(ignored.unsqueeze(-1), 0)
        classification_loss = self.bce(scores, classification_targets.to(dtype))
        classification_loss = classification_loss.masked_fill(ignored.unsqueeze(-1), 0)
        weight_sum = weights.sum().clamp_(min=1)
        classification_weight = classification_targets.sum().clamp_(min=1)
        loss[1] = classification_loss.sum() / classification_weight
        loss[0], loss[2] = self.bbox_loss(
            distribution, predicted_boxes, anchors, assigned_boxes / strides,
            weights, weight_sum, foreground, image_size, strides)
        loss[0] *= self.hyp.box
        loss[1] *= self.hyp.cls
        loss[2] *= self.hyp.dfl
        if SELF_CHECK:
            known = foreground & ~ignored
            self.audit['ignored_anchors'] += int(ignored.sum())
            self.audit['known_anchors'] += int(known.sum())
            self.audit['ignored_target_sum'] += float(classification_targets[ignored].sum())
            self.audit['ignored_cls_loss'] += float(classification_loss[ignored].sum().detach())
            self.audit['known_cls_loss'] += float(classification_loss[known].sum().detach())
        return ((foreground, target_indices, assigned_boxes, anchors, strides), loss,
                dict(zip(('box_loss', 'cls_loss', 'dfl_loss'), loss.detach())))


def init_masked_criterion(model):
    return MaskedPoseLoss(model)


class MaskedTrainer(PoseTrainer):
    def build_dataset(self, img_path, mode='train', batch=None):
        stride = max(int(unwrap_model(self.model).stride.max()), 32)
        return MaskedDataset(
            img_path=img_path, imgsz=self.args.imgsz, batch_size=batch,
            augment=mode == 'train', hyp=self.args, rect=self.args.rect or mode == 'val',
            cache=self.args.cache or None, single_cls=False, stride=stride,
            pad=0.0 if mode == 'train' else 0.5, prefix=colorstr(f'{mode}: '),
            task='pose', classes=self.args.classes, data=self.data,
            fraction=self.args.fraction if mode == 'train' else 1.0)

    def save_model(self):
        # Keep checkpoints portable: only the native model and its usual parameters are saved.
        self.ema.ema.criterion = None
        super().save_model()

    def plot_training_labels(self):
        names = self.data['names']
        self.data['names'] = {**names, IGNORE_CLASS: 'ignore_class'}
        super().plot_training_labels()
        self.data['names'] = names


def audit_epoch(trainer):
    audit = unwrap_model(trainer.model).criterion.audit
    losses = {name: float(value) for name, value in trainer.tloss.items()}
    assert all(math.isfinite(value) for value in losses.values()), losses
    assert audit['ignored_anchors'] > 0, audit
    assert audit['known_anchors'] > 0, audit
    assert audit['ignored_target_sum'] == 0, audit
    assert audit['ignored_cls_loss'] == 0, audit
    assert audit['known_cls_loss'] > 0, audit
    result = dict(audit, losses=losses, nc=trainer.model.model[-1].nc,
                  kpt_shape=trainer.model.model[-1].kpt_shape)
    print('MASKED_SELF_CHECK_JSON', json.dumps(result), flush=True)
    (trainer.save_dir / 'masked-self-check.json').write_text(json.dumps(result, indent=2))


def main():
    global SELF_CHECK
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-check', type=Path)
    parser.add_argument('--resume', action='store_true')
    args = parser.parse_args()
    SELF_CHECK = args.self_check is not None
    PoseModel.init_criterion = init_masked_criterion
    root = Path('/root/edrv32')
    weights = root / ('runs/hand-orient-v8n/weights/last.pt' if args.resume else
                      'runs/hagrid-v8n-r2/weights/best.pt')
    model = YOLO(str(weights))
    if SELF_CHECK:
        model.add_callback('on_train_epoch_end', audit_epoch)
    started = datetime.now(timezone.utc)
    print('TRAIN_START', started.isoformat(), flush=True)
    if args.resume:
        model.train(trainer=MaskedTrainer, resume=True)
    else:
        model.train(trainer=MaskedTrainer,
                    data=str(args.self_check or root / 'hand-orient/mixed/hand-orient.yaml'),
                    epochs=1 if SELF_CHECK else 30, imgsz=640,
                    batch=16 if SELF_CHECK else 128, workers=2 if SELF_CHECK else 16,
                    cache=False, seed=0, deterministic=True, project=str(root / 'runs'),
                    name='hand-orient-self-check' if SELF_CHECK else 'hand-orient-v8n')
    ended = datetime.now(timezone.utc)
    print('TRAIN_TIMING_JSON', json.dumps(dict(start=started.isoformat(), end=ended.isoformat(),
                                              seconds=(ended-started).total_seconds())), flush=True)


if __name__ == '__main__':
    main()
