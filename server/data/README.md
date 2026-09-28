# server/data

- `cities.tsv` — global city directory built from GeoNames `cities15000` (CC BY 4.0, https://www.geonames.org/) by `tools/build_cities.mjs`. Suburbs inside a much larger city's radius are merged so a metro area is one city.
  Rebuild: download `cities15000.zip`, `admin1CodesASCII.txt` and `countryInfo.txt` from https://download.geonames.org/export/dump/ and run `node tools/build_cities.mjs cities15000.txt admin1CodesASCII.txt countryInfo.txt`.
- The IP city database (DB-IP City Lite, CC BY 4.0, https://db-ip.com) is **not** committed (~130 MB). Download `dbip-city-lite-YYYY-MM.mmdb.gz` from https://download.db-ip.com/free/, gunzip it on the server and point `IP_CITY_DB` at it.
