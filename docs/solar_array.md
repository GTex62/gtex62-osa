# SOL ARRAY

Labels:

- UV  = UV index
- VI  = visible sunlight intensity
- IR  = infrared heat energy
- CL  = cloud cover
- RAD = total solar radiation (W/m²)

## Source strategy

### UV and RAD — Open-Meteo (primary)

`fetch_solar.sh` fetches UV index and shortwave radiation from
[Open-Meteo](https://open-meteo.com/) on each refresh cycle:

```text
GET https://api.open-meteo.com/v1/forecast
    ?latitude=<lat>&longitude=<lon>
    &current=uv_index,shortwave_radiation
    &timezone=auto&forecast_days=1
```

No API key or account required. Open-Meteo is open-source and does not collect
telemetry. UV is sourced from CAMS (Copernicus Atmosphere Monitoring Service)
satellite data. Shortwave radiation is real-time modeled GHI (global horizontal
irradiance) in W/m².

If the fetch fails (no network, timeout), both values fall back to the
synthetic model described below.

Fields consumed:

- `current.uv_index` → `values.UV` / `norm.UV`
- `current.shortwave_radiation` → `values.RAD` / `norm.RAD`

### UV and RAD — Synthetic fallback

When Open-Meteo is unavailable, UV and RAD are derived from OWM current weather
using a geometric solar model.

Inputs:

- `dt`, `sys.sunrise`, `sys.sunset` (timestamp and day bounds)
- `clouds.all` (cloud cover %)
- `main.temp` (temperature, for IR)
- `lat` (from profile or `site.toml`, for seasonal UV scaling)

Derived factors:

- `sun_factor` — sine of the elapsed fraction of the solar day, peaks at 1.0
  at solar noon
- `cloud_factor` — `1 - clouds/100`
- `visible_factor` — `sun_factor × cloud_factor`

UV synthetic formula:

```text
uv_noon_max = 11 × cos²(zenith_noon)
zenith_noon = |latitude − solar_declination|
solar_declination = 23.45° × sin(2π × (DOY − 81) / 365)

UV = uv_noon_max × sun_factor × cloud_factor
```

`cos²(zenith_noon)` scales the 11-point maximum by latitude and season:
mid-latitude winter drops to ~3, peak summer approaches 10–11.

RAD synthetic formula:

```text
RAD = 1000 × visible_factor  (W/m² proxy)
```

### VI, IR, CL — always synthetic

These three labels have no external source and remain weather-derived on every
run.

Inputs (from OWM current weather):

- `dt`, `sys.sunrise`, `sys.sunset`
- `clouds.all`
- `main.temp`

Derived:

- `VI` → `100 × visible_factor`
- `IR` → `100 × sun_factor × (0.65 × cloud_factor + 0.35 × temp_factor)`
  where `temp_factor = clamp((temp_f − 20) / 80, 0, 1)`
- `CL` → `clouds.all`

## Output schema

`~/.cache/gtex62-core/shared/solar/<profile>/current.json`

```json
{
  "values": {
    "UV":  7.2,
    "VI":  99.99,
    "IR":  90.63,
    "CL":  0,
    "RAD": 990.0
  },
  "norm": {
    "UV":  0.65,
    "VI":  1.0,
    "IR":  0.91,
    "CL":  0,
    "RAD": 0.99
  },
  "meta": {
    "uv_source": "open-meteo"
  }
}
```

`norm` values are in the range 0–1 and are used for bar/meter fill.
`meta.uv_source` is `"open-meteo"` when real data was fetched, `"synthetic"`
when the fallback ran.

## ENV panel status line

The ENV panel SRC line includes a solar source token:

- `| MET` — UV and RAD are live Open-Meteo data
- `| DRV` — UV and RAD are from the synthetic fallback

Example: `SRC // OWM BASE | ANW AQI PM2.5 | MET`

## Normalization ranges

- UV  : 0–11 (WHO UV index scale)
- VI  : 0–100 (proxy %)
- IR  : 0–100 (proxy %)
- CL  : 0–100 %
- RAD : 0–1000 W/m²

## Expected behavior

Clear summer day at solar noon:

- UV high (7–10, real from Open-Meteo)
- VI high
- IR moderate/high
- CL low
- RAD high (800–1000 W/m², real from Open-Meteo)

Overcast day:

- UV low (real, cloud-attenuated)
- VI low
- IR low
- CL high
- RAD low (real, may be near 0 under heavy overcast)

Night:

- UV 0
- VI 0
- IR 0
- CL whatever clouds.all reports
- RAD 0
