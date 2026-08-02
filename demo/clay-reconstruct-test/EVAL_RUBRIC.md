# Fixed Evaluation Rubric — Clay Moped Reconstruction

Use this rubric for ALL iterations. Score strictly against these criteria.

## Reference: A Chinese urban electric moped (red, parked on sidewalk)
Key identifying features:
- Low-slung step-through frame body
- Rounded/curved body panels (not angular/boxy)
- Two thin bicycle-style wheels with black rubber tires
- Black elongated seat cushion
- Chrome handlebar with round mirrors on stalks
- Wire basket mounted on front fork
- Thin chrome rear rack
- Small round headlight
- Small red taillight
- Front and rear fenders over wheels
- Kickstand deployed

## Scoring Criteria (0-1 each)

### 1. Overall Fidelity
- 0.95+: Indistinguishable from reference at thumbnail size, reads as same vehicle
- 0.85-0.94: Clearly the same vehicle type, minor differences only
- 0.70-0.84: Recognizably a moped, but several features differ
- 0.50-0.69: Generic vehicle shape, missing defining characteristics
- 0.30-0.49: Vaguely vehicle-shaped
- <0.30: Not recognizable

### 2. Silhouette Match
- 0.95+: Outline traces reference almost exactly
- 0.85-0.94: Major curves match, minor proportions off
- 0.70-0.84: General shape correct, several curves wrong
- 0.50-0.69: Recognizable as vehicle but wrong proportions
- <0.50: Wrong shape

### 3. Component Accuracy
Count visible components that match reference. Score = matched/total.
- Body shell, seat, 2 wheels, handlebar, 2 mirrors, basket, headlight, taillight, front fender, rear fender, rear rack, kickstand, floorboard, fork
- Total ~15 components. Score = (count present and recognizable) / 15

### 4. Color Accuracy
- 0.95+: All colors match reference exactly
- 0.85-0.94: All major colors correct, minor hue shift
- 0.70-0.84: Most colors correct, one or two wrong
- <0.70: Multiple color errors

### 5. Material Response
Clay style is intentional. Evaluate whether:
- Different surfaces read as different materials (plastic vs rubber vs chrome vs glass)
- Body has slight gloss (clearcoat)
- Tires read as matte rubber
- Chrome/metal parts read as metallic
- Seat reads as vinyl/leather (not same as body)
- 0.95+: All 5 material zones clearly differentiated
- 0.85-0.94: 4 of 5 zones differentiated
- 0.70-0.84: 3 of 5 zones differentiated
- <0.70: <3 zones differentiated

### 6. Proportion Accuracy
- 0.95+: All proportions match reference within 10%
- 0.85-0.94: Most proportions correct, one feature off
- 0.70-0.84: Several proportions wrong
- <0.70: Major proportion errors

## Output Format
```
OVERALL: X.XX
SILHOUETTE: X.XX
COMPONENT: X.XX
COLOR: X.XX
MATERIAL: X.XX
PROPORTION: X.XX
COMPOSITE: X.XX (average of above)
ACTION: continue|stop
TOP3: [issue1, issue2, issue3]
```
