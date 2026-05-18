# METAR AO2 / RMK Practical Reference

ASOS / AWOS – Station Model Oriented

This reference covers **U.S. METAR RMK groups**, especially those reported by **AO2** stations (automated with precipitation discriminator).

**Focus:**
Only operationally useful groups that appear in real-world data and matter for station models.

---

## 1. Station Type

### AO1 / AO2

| Code | Meaning |
| -- | -- |
| AO1 | Automated, no precipitation discriminator |
| AO2 | Automated, with precipitation discriminator |

**Note:** Most extended RMK groups appear only with **AO2**.

---

## 2. Pressure & Barometric Trend

### 2.1 Sea-Level Pressure (SLP)

```text
SLP218 → 1021.8 hPa
```

```text
SLPnnn
```

#### Decoding Rule

- nnn ≥ 500 → prefix `9`
- nnn < 500 → prefix `10`

#### Examples

| Code   | Result     |
| ------ | ---------- |
| SLP982 | 998.2 hPa  |
| SLP306 | 1030.6 hPa |

**Station Model:**
Plot only the **3-digit code** (e.g., `218`, `306`).

---

### 2.2 Pressure Tendency (3-Hour Trend)

```text
58012
```

```text
5appp
```

| Part | Meaning              |
| ---- | -------------------- |
| 5    | Tendency group       |
| a    | Character (0–8)      |
| ppp  | Change in tenths hPa |

#### Example

```text
58012 → Character 8, +1.2 hPa
```

#### Tendency Codes

| a | Description             |
| - | ----------------------- |
| 0 | Rising, then falling    |
| 1 | Rising, then steady     |
| 2 | Rising                  |
| 3 | Falling/steady → rising |
| 4 | Steady                  |
| 5 | Falling → rising        |
| 6 | Falling → steady        |
| 7 | Falling                 |
| 8 | Steady/rising → falling |

**Used For:**

- Trend glyph (a₀–a₈)
- Numeric delta (± hPa)

---

## 3. Temperature & Humidity

### 3.1 Precise Temperature / Dewpoint (T Group)

```text
T10561178 → -5.6°C / -17.8°C
```

```text
TsnTTTsnTTT
```

| Field | Meaning      |
| ----- | ------------ |
| sn    | 0 = +, 1 = – |
| TTT   | Tenths °C    |

More precise than `M06/M18`.

---

### 3.2 6-Hour Max / Min Temperature

```text
11078 → Max -7.8°C
21089 → Min -8.9°C
```

| Code   | Meaning  |
| ------ | -------- |
| 1snTTT | 6-hr max |
| 2snTTT | 6-hr min |

---

### 3.3 24-Hour Max / Min Temperature

```text
400561056 → +5.6°C / -5.6°C
```

```text
4snTTTsnTTT
```

---

## 4. Precipitation & Hydrology

### 4.1 Hourly Precipitation (1 Hour)

```text
P0012 → 0.12"
```

```text
Prrrr
```

- rrrr = hundredths of inches

---

### 4.2 6-Hour Precipitation

```text
60023 → 0.23"
6//// → missing
```

```text
6RRRR
```

Widget Convention:

- Missing → `/`

---

### 4.3 24-Hour Precipitation

```text
70045 → 0.45"
```

```text
7RRRR
```

---

### 4.4 Snow Depth on Ground

```text
4/003 → 3 inches
```

```text
4/sss
```

- sss = inches
- /// = missing

---

### 4.5 Water Equivalent of Snow

```text
933009 → 0.9"
```

```text
933sss
```

- sss = tenths of inches

Requires special sensor.

---

### 4.6 Ice Accretion

```text
I1001 → 0.01"
I6005 → 0.05"
```

| Code  | Period  |
| ----- | ------- |
| I1nnn | 1 hour  |
| I6nnn | 6 hours |

Units: hundredths of inches

---

## 5. Weather Timing (Begin / End)

### 5.1 Precipitation Begin / End

```text
RAB05    → Began :05
RAE42    → Ended :42
SNB12E38 → Began :12, Ended :38
```

```text
<wx>Bmm
<wx>Emm
<wx>BmmEmm
```

Used for past-weather logic.

---

### 5.2 Present Weather RMK Timing

```text
TSB15E47
PLB53
SHRAB22
```

Same timing logic, applied to present wx.

---

## 6. Cloud & Visibility Information

### 6.1 Ceiling Variability

```text
CIG 008V013
```

Meaning: 800–1300 ft ceiling.

Informational only; rarely plotted.

---

## 7. Sensor Status & Maintenance

### 7.1 Sensor Availability

| Code   | Meaning                   |
| ------ | ------------------------- |
| PNO    | Precip sensor inoperative |
| FZRANO | FZRA sensor unavailable   |
| RVRNO  | RVR unavailable           |
| $      | Maintenance required      |

Useful for diagnostics and confidence scoring.

---

## 8. Lightning Reports (Rare)

| Code      | Meaning                |
| --------- | ---------------------- |
| LTG DSNT  | Distant                |
| LTG CG    | Cloud–ground           |
| LTG IC    | In-cloud               |
| LTG ALQDS | All quadrants, distant |

Appears mostly at major stations.

---

## 9. Station Model Integration

### 9.1 High-Value Groups

Implemented / Planned:

- ✔ Sea-level pressure (SLP)
- ✔ Pressure tendency (5appp)
- ✔ Present weather + intensity
- ✔ 6-hour precip
- ✔ Temp/Dew (T group optional)
- ✔ Ice accretion (v2)
- ✔ 6-hr / 24-hr temps (v2)

---

### 9.2 Rendering Rules (Project Convention)

1. If data present → render normally
2. If missing (e.g., `6////`) → display `/`
3. Never block rendering due to missing RMK fields

Ensures robustness in degraded data environments.

---

## 10. Scope & Sources

This reference reflects operational practice from:

- NWS ASOS User Guide
- FAA 7900.5 / 7110.65
- Live ASOS/AWOS observations

It intentionally excludes obscure or academic RMK groups that rarely appear in production data.
