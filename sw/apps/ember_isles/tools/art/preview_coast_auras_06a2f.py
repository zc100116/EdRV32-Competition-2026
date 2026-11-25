#!/usr/bin/env python3
"""06a-2f acceptance: GPU readback, 28 pairs and unchanged 806d51110 RGBA.
Host standard library; one complete conversion, six I4 frames for every affix.
Only fanatic, reflect and dim are excluded from the previous-frame comparison.
"""
import preview_coast_auras_06a2e as review


def main():
    review.BASELINE = '806d51110'
    review.BUILD = review.ROOT / 'build/ember_isles/art_coast_auras_06a2f'
    review.OUTPUT = review.ROOT / 'outputs/ember_isles/art3-coast-assets/06a2e/06a2f'
    review.production.BUILD = review.BUILD
    review.production.main()
    review.budget.BUILD = review.BUILD
    review.budget.main()
    review.main(tuple('elite_aura_' + affix for affix in ('fanatic', 'reflect', 'dim')))


if __name__ == '__main__':
    main()
