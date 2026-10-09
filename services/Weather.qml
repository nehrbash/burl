pragma Singleton

import QtQuick
import Quickshell
import Burl
import Burl.Config
import qs.utils

Singleton {
    id: root

    property string city
    property string loc
    property bool locating: false
    property string locationError
    property int locationRequest: 0
    property string requestedLocation
    property var cc
    property list<var> forecast
    property list<var> hourlyForecast

    readonly property real moonPhase: cc?.moonPhase ?? -1

    readonly property string icon: cc ? Icons.getWeatherIcon(cc.weatherCode) : "cloud_alert"
    readonly property string description: cc?.weatherDesc ?? qsTr("No weather")
    readonly property string temp: formatTemp(cc?.tempC)
    readonly property string feelsLike: formatTemp(cc?.feelsLikeC)
    readonly property int humidity: cc?.humidity ?? 0
    readonly property real windSpeed: cc?.windSpeed ?? 0
    readonly property string sunrise: cc ? Qt.formatDateTime(new Date(cc.sunrise), GlobalConfig.services.useTwelveHourClock ? "h:mm A" : "h:mm") : "--:--"
    readonly property string sunset: cc ? Qt.formatDateTime(new Date(cc.sunset), GlobalConfig.services.useTwelveHourClock ? "h:mm A" : "h:mm") : "--:--"

    readonly property var cachedCities: new Map()

    function formatTemp(temp: var): string {
        return GlobalConfig.services.useFahrenheit ? `${temp !== undefined ? Math.round(toFahrenheit(temp)) : "--"}°F` : `${temp !== undefined ? Math.round(temp) : "--"}°C`;
    }

    function validCoordinates(value: string): bool {
        const parts = value.split(",").map(s => s.trim());
        return parts.length === 2 && parts.every(s => /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$/.test(s))
            && Math.abs(Number(parts[0])) <= 90 && Math.abs(Number(parts[1])) <= 180;
    }

    function locationFailed(request: int, message: string): void {
        if (request !== locationRequest)
            return;
        locating = false;
        locationError = message;
    }

    function reload(force: bool): void {
        const configLocation = GlobalConfig.services.weatherLocation.trim();
        const changed = configLocation !== requestedLocation;
        if (!force && !changed && (locating || (!configLocation && loc && timer.elapsed() <= 900)))
            return;

        const request = ++locationRequest;
        requestedLocation = configLocation;
        locating = true;
        locationError = "";
        if (changed) {
            loc = "";
            city = "";
            cc = null;
            forecast = [];
            hourlyForecast = [];
        }
        if (configLocation) {
            if (/^[+-]?[\d.]+\s*,/.test(configLocation)) {
                if (!validCoordinates(configLocation)) {
                    locationFailed(request, qsTr("Enter latitude from −90 to 90 and longitude from −180 to 180."));
                    return;
                }
                loc = configLocation;
                locating = false;
                fetchCityFromCoords(configLocation, request);
            } else {
                fetchCoordsFromCity(configLocation, request);
            }
        } else {
            Requests.get("https://ipinfo.io/json", text => {
                if (request !== root.locationRequest)
                    return;
                const response = root._json(text);
                if (response?.loc && root.validCoordinates(response.loc)) {
                    loc = response.loc;
                    city = response.city ?? "";
                    locating = false;
                    timer.restart();
                } else {
                    root.locationFailed(request, qsTr("Could not detect your location. Enter a city or coordinates."));
                }
            }, () => root.locationFailed(request, qsTr("Location detection failed. Check your connection and retry.")));
        }
    }

    function _json(text: string): var {
        try {
            return JSON.parse(text);
        } catch (e) {
            return null;
        }
    }

    function fixCityName(cityName: string): string {
        if (!cityName)
            return "";
        const mapping = {
            // Polish
            "Poznan": "Poznań",
            "Wroclaw": "Wrocław",
            "Krakow": "Kraków",
            "Gdansk": "Gdańsk",
            "Lodz": "Łódź",
            "Rzeszow": "Rzeszów",
            "Torun": "Toruń",
            "Bialystok": "Białystok",
            "Czestochowa": "Częstochowa",
            "Plock": "Płock",
            "Ruda Slaska": "Ruda Śląska",
            "Dabrowa Gornicza": "Dąbrowa Górnicza",
            "Elblag": "Elbląg",
            "Gorzow Wielkopolski": "Gorzów Wielkopolski",
            "Zielona Gora": "Zielona Góra",
            "Slupsk": "Słupsk",

            // German
            "Munchen": "München",
            "Koln": "Köln",
            "Dusseldorf": "Düsseldorf",
            "Nurnberg": "Nürnberg",

            // French & Spanish & Portuguese
            "Sao Paulo": "São Paulo",
            "Montreal": "Montréal",
            "Quebec": "Québec",
            "Bogota": "Bogotá",
            "Medellin": "Medellín",
            "Cordoba": "Córdoba",

            // Turkish
            "Istanbul": "İstanbul",
            "Izmir": "İzmir",

            // Scandinavian & others
            "Malmo": "Malmö",
            "Goteborg": "Göteborg",
            "Zurich": "Zürich",
            "Geneve": "Genève"
        };
        return mapping[cityName] || cityName;
    }

    function fetchCityFromCoords(coords: string, request: int): void {
        if (cachedCities.has(coords)) {
            city = cachedCities.get(coords);
            return;
        }

        const [lat, lon] = coords.split(",").map(s => s.trim());
        const lang = Qt.locale().name.split("_")[0] || "en";

        const fallbackToBigDataCloud = () => {
            if (request !== root.locationRequest)
                return;
            const fallbackUrl = `https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=${lat}&longitude=${lon}&localityLanguage=${lang}`;
            Requests.get(fallbackUrl, text => {
                if (request !== root.locationRequest)
                    return;
                const geo = root._json(text);
                const geoCity = geo?.city || geo?.locality;
                if (geoCity) {
                    city = fixCityName(geoCity);
                    cachedCities.set(coords, city);
                } else {
                    city = "Unknown City";
                }
            });
        };

        const nominatimUrl = `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lon}&format=geocodejson&accept-language=${lang}`;
        Requests.get(nominatimUrl, text => {
            if (request !== root.locationRequest)
                return;
            const geo = root._json(text)?.features?.[0]?.properties?.geocoding;
            if (geo) {
                const geoCity = geo.type === "city" ? geo.name : geo.city;
                if (geoCity) {
                    city = fixCityName(geoCity);
                    cachedCities.set(coords, city);
                    return;
                }
            }
            fallbackToBigDataCloud();
        }, fallbackToBigDataCloud);
    }

    function fetchCoordsFromCity(cityName: string, request: int): void {
        const lang = Qt.locale().name.split("_")[0] || "en";
        const url = `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(cityName)}&count=1&language=${lang}&format=json`;

        Requests.get(url, text => {
            if (request !== root.locationRequest)
                return;
            const json = root._json(text);
            const result = json?.results?.[0];
            if (result && root.validCoordinates(result.latitude + "," + result.longitude)) {
                loc = result.latitude + "," + result.longitude;
                city = fixCityName(result.name);
                locating = false;
            } else {
                root.locationFailed(request, qsTr("Location not found. Try another city or latitude, longitude."));
            }
        }, () => root.locationFailed(request, qsTr("Location lookup failed. Check your connection and retry.")));
    }

    function fetchWeatherData(): void {
        const url = getWeatherUrl();
        if (url === "")
            return;

        const weatherLocation = loc;
        Requests.get(url, text => {
            if (weatherLocation !== root.loc)
                return;
            const json = root._json(text);
            if (!json?.current || !json.daily)
                return;

            cc = {
                moonPhase: parseMoonPhase(json.daily),
                weatherCode: json.current.weather_code,
                weatherDesc: getWeatherCondition(json.current.weather_code),
                tempC: json.current.temperature_2m,
                feelsLikeC: json.current.apparent_temperature,
                humidity: json.current.relative_humidity_2m,
                windSpeed: json.current.wind_speed_10m,
                isDay: json.current.is_day,
                sunrise: json.daily.sunrise[0].replace("T", " "),
                sunset: json.daily.sunset[0].replace("T", " ")
            };

            const forecastList = [];
            for (let i = 0; i < json.daily.time.length; i++)
                forecastList.push({
                    date: json.daily.time[i].replace(/-/g, "/"),
                    maxTempC: json.daily.temperature_2m_max[i],
                    minTempC: json.daily.temperature_2m_min[i],
                    weatherCode: json.daily.weather_code[i],
                    icon: Icons.getWeatherIcon(json.daily.weather_code[i])
                });
            forecast = forecastList;

            const hourlyList = [];
            const now = new Date();
            for (let i = 0; i < json.hourly.time.length; i++) {
                const time = new Date(json.hourly.time[i].replace("T", " "));

                if (time < now)
                    continue;

                hourlyList.push({
                    timestamp: json.hourly.time[i],
                    hour: time.getHours(),
                    tempC: Math.round(json.hourly.temperature_2m[i]),
                    precipChance: json.hourly.precipitation_probability[i],
                    weatherCode: json.hourly.weather_code[i],
                    icon: Icons.getWeatherIcon(json.hourly.weather_code[i])
                });
            }
            hourlyForecast = hourlyList;
        });
    }

    function parseMoonPhase(daily: var): real {
        const phase = daily?.moon_phase?.[0];
        return typeof phase === "number" && Number.isFinite(phase) && phase >= 0 && phase <= 1 ? phase : -1;
    }

    function toFahrenheit(celcius: real): real {
        return celcius * 9 / 5 + 32;
    }

    function getWeatherUrl(): string {
        if (!loc || loc.indexOf(",") === -1)
            return "";

        const [lat, lon] = loc.split(",").map(s => s.trim());
        const baseUrl = "https://api.open-meteo.com/v1/forecast";
        const params = ["latitude=" + lat, "longitude=" + lon, "hourly=weather_code,temperature_2m,precipitation_probability", "daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,moon_phase", "current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m", "timezone=auto", "forecast_days=7"];

        return baseUrl + "?" + params.join("&");
    }

    function getWeatherCondition(code: string): string {
        const conditions = {
            "0": "Clear",
            "1": "Clear",
            "2": "Partly cloudy",
            "3": "Overcast",
            "45": "Fog",
            "48": "Fog",
            "51": "Drizzle",
            "53": "Drizzle",
            "55": "Drizzle",
            "56": "Freezing drizzle",
            "57": "Freezing drizzle",
            "61": "Light rain",
            "63": "Rain",
            "65": "Heavy rain",
            "66": "Light rain",
            "67": "Heavy rain",
            "71": "Light snow",
            "73": "Snow",
            "75": "Heavy snow",
            "77": "Snow",
            "80": "Light rain",
            "81": "Rain",
            "82": "Heavy rain",
            "85": "Light snow showers",
            "86": "Heavy snow showers",
            "95": "Thunderstorm",
            "96": "Thunderstorm with hail",
            "99": "Thunderstorm with hail"
        };
        return conditions[code] || "Unknown";
    }

    onLocChanged: fetchWeatherData()

    Connections {
        function onWeatherLocationChanged(): void {
            root.reload(true);
        }

        target: GlobalConfig.services
    }

    Timer {
        interval: 3600000 // 1 hour
        running: true
        repeat: true
        onTriggered: fetchWeatherData()
    }

    ElapsedTimer {
        id: timer
    }
}
