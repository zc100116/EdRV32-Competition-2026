#!/usr/bin/env python3
"""check_masked_assigner.py: supplement 2, test maximum-score unknown alignment.
Clock domain: not applicable (CPU unit check).
"""
import torch
from train_masked import MaskedAssigner

assigner = MaskedAssigner(topk=2, topk2=2, num_classes=14, alpha=0.5, beta=6)
assigner.bs, assigner.n_max_boxes = 1, 1
scores = torch.full((1, 2, 14), 0.01)
scores[..., 0] = 0.1
scores[..., 7] = 0.9
boxes = torch.tensor([[[0., 0., 10., 10.], [0., 0., 10., 10.]]])
gt_boxes = boxes[:, :1]
mask = torch.ones(1, 1, 2, dtype=torch.bool)
unknown = torch.tensor([[[14.]]])
known = torch.tensor([[[0.]]])
unknown_metric, _ = assigner.get_box_metrics(scores, boxes, unknown, gt_boxes, mask)
known_metric, _ = assigner.get_box_metrics(scores, boxes, known, gt_boxes, mask)
torch.testing.assert_close(unknown_metric, torch.full((1, 1, 2), 0.9 ** 0.5))
torch.testing.assert_close(known_metric, torch.full((1, 1, 2), 0.1 ** 0.5))
result = assigner(scores, boxes, torch.tensor([[2., 2.], [7., 7.]]), unknown,
                  gt_boxes, torch.ones(1, 1, 1))
assert torch.all(result[0] == 14)
assert torch.all(result[3])
assert result[2].sum() > 0
print('MASKED_ASSIGNER_PASS', 'unknown_metric', unknown_metric.tolist(),
      'known_metric', known_metric.tolist(), 'box_weight_sum', float(result[2].sum()))
