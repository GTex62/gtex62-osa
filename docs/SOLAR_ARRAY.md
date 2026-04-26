# SOL ARRAY

Labels:

- UV  = UV index
- VI  = visible sunlight intensity
- IR  = infrared heat energy
- CL  = cloud cover
- RAD = total solar radiation

## Source strategy

### Current implementation

Uses only `owm_current.json` and derives a solar-behavior model.

Inputs (from current weather):

- `dt`
- `sys.sunrise`
- `sys.sunset`
- `clouds.all`
- `main.temp`

Temperature handling:
  `main.temp` is converted using `UNITS` from `config/owm.vars` (`imperial`/`metric`), with Kelvin fallback if unset.

Derived:

- sun_factor -> based on sunrise/sunset and current time
- UV  -> `11 * sun_factor`
- CL  -> `clouds.all`
- VI  -> `sun_factor * (1 - clouds/100)`
- RAD -> `sun_factor * (1 - clouds/100)`
- IR  -> `sun_factor * (1 - clouds/100)` combined with temperature factor

## Expected behavior

Clear summer day:

- UV high
- VI high
- IR moderate/high
- CL low
- RAD high

Overcast day:

- UV low
- VI low
- IR low
- CL high
- RAD low

Passing clouds:

- UV medium
- VI fluctuating
- IR medium
- CL medium/high
- RAD fluctuating

## Upgrade path

If OpenWeather Solar Irradiance API is added later:

- RAD -> real GHI
- VI  -> derive from GHI/DHI
- IR  -> derive from GHI + temperature
- CL  -> keep from weather data
- UV  -> keep derived or replace with One Call if added back

## Suggested normalization ranges

- UV  : 0..11
- VI  : 0..100 (proxy)
- IR  : 0..100 (proxy)
- CL  : 0..100 %
- RAD : 0..1000 W/m^2 (proxy until GHI is available)
