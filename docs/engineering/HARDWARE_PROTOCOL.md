# Hardware Protocol

The optional hardware boundary exposes connection, battery, shutter, and rotary
events as domain values. The MVP uses `MockHardwareController`; no CoreBluetooth
calls are made.

The future real implementation must translate raw rotary deltas into normalized
rail deltas. It must not send fixed time-anchor enums because the product control
is continuous.
