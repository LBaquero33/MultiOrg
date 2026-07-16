# TrackMan Radar Import Mapping

Semantics and units follow TrackMan's official [Radar Glossary of Terms](https://support.trackmanbaseball.com/hc/en-us/articles/5089413493787-Radar-Glossary-Of-Terms). Staff must confirm Imperial or Metric; values are never classified by magnitude. Changing the unit system or time zone invalidates the previous preview.

Mappings: `RelSpeed`→pitch velocity, `SpinRate`→spin rate, `RelHeight/RelSide/Extension`→release measures, `InducedVertBreak`→induced vertical break, `HorzBreak`→horizontal break, `PlateLocHeight/Side`→plate location, `ZoneSpeed`→zone velocity, `VertApprAngle/HorzApprAngle`→approach angles, and `ExitSpeed/Angle/Direction/HitSpinRate/Distance`→hitting event metrics.

Imperial speed/distance/movement units are mph/feet/inches; Metric exports use km/h/metres/centimetres. Angles remain degrees and spin remains rpm. `VertBreak` is not `InducedVertBreak`; `pfxx/pfxz` describe only the last 40 feet and are not synonyms for full-flight break.

`UTCDateTime` is preferred. `LocalDateTime` is accepted only when its documented offset is present. Pitcher and batter provider IDs are matched independently per row and metric category.
