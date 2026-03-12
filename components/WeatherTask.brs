sub init()
    m.top.functionName = "runTask"
end sub

sub runTask()
    m.port = CreateObject("roMessagePort")
    m.top.observeField("status", m.port)
    
    fetchWeather()

    while true
        msg = wait(1000, m.port)
        if type(msg) = "roSGNodeEvent" then
            if msg.getField() = "status" then
                if msg.getData() = "REFRESH" then
                    fetchWeather()
                end if
            end if
        else if msg = invalid then
            sleep(100)
        end if
    end while
end sub

sub fetchWeather()
    cfg = GetConfig()
    lat = ""
    lon = ""
    city = ""

    ' 1. Try config first
    if cfg.weather <> invalid then
        lat = cfg.weather.latitude
        lon = cfg.weather.longitude
        city = cfg.weather.city
    end if

    ' 2. Fallback to GeoIP if config is empty
    if lat = "" or lon = "" then
        xfer = CreateObject("roUrlTransfer")
        xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
        xfer.SetUrl("http://ip-api.com/json")
        resp = xfer.GetToString()
        if resp <> "" then
            loc = ParseJson(resp)
            if loc <> invalid then
                if loc.lat <> invalid and loc.lon <> invalid then
                    lat = (loc.lat).ToStr()
                    lon = (loc.lon).ToStr()
                    city = loc.city
                end if
            end if
        end if
    end if

    if lat = "" or lon = "" then
        return
    end if
    
    ' 3. Get Weather via Open-Meteo
    url = "https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon + "&current_weather=true&temperature_unit=fahrenheit"
    xfer = CreateObject("roUrlTransfer")
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.SetUrl(url)
    resp = xfer.GetToString()
    if resp = "" then
        return
    end if
    
    w = ParseJson(resp)
    if w = invalid or w.current_weather = invalid then
        return
    end if
    
    curr = w.current_weather
    tempVal = Int(curr.temperature)
    temp = (tempVal).ToStr() + "°F"
    code = curr.weathercode
    
    ' WMO Weather interpretation
    cond = "Clear"
    if code = 1 or code = 2 or code = 3 then
        cond = "Partly Cloudy"
    end if
    if code >= 45 and code <= 48 then
        cond = "Foggy"
    end if
    if code >= 51 and code <= 67 then
        cond = "Rainy"
    end if
    if code >= 71 and code <= 77 then
        cond = "Snowy"
    end if
    if code >= 80 and code <= 82 then
        cond = "Showers"
    end if
    if code >= 95 then
        cond = "Stormy"
    end if
    
    m.top.temp = temp
    m.top.condition = cond + " in " + city
end sub
