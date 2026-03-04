sub init()
    m.top.functionName = "runTask"
    cfg = GetConfig()
    m.appKey = cfg.dropbox.appKey
end sub

sub runTask()
    ' Check for existing tokens once at startup
    loadSavedTokens()
    
    ' Set up a message port to listen for field changes
    m.port = CreateObject("roMessagePort")
    m.top.observeField("status", m.port)
    
    while true
        msg = wait(0, m.port)
        if type(msg) = "roSGNodeEvent" and msg.getField() = "status" then
            status = m.top.status
            if status = "AUTHENTICATE" then
                getDeviceCode()
            else if status = "FETCH_PHOTOS" then
                fetchDropboxPhotos()
            end if
        end if
    end while
end sub

' --- Persistence ---
function loadSavedTokens() as boolean
    sec = CreateObject("roRegistrySection", "Authentication")
    if sec.Exists("db_refresh_token") then
        m.refreshToken = sec.Read("db_refresh_token")
        m.accessToken = sec.Read("db_access_token")
        m.top.status = "SUCCESS" ' Signal we are logged in
        return true
    end if
    return false
end function

sub saveTokens(json as object)
    sec = CreateObject("roRegistrySection", "Authentication")
    if json.refresh_token <> invalid then 
        m.refreshToken = json.refresh_token
        sec.Write("db_refresh_token", json.refresh_token)
    end if
    if json.access_token <> invalid then 
        m.accessToken = json.access_token
        sec.Write("ms_access_token", json.access_token) ' Wait, MS typo? DB!
        sec.Write("db_access_token", json.access_token)
    end if
    sec.Flush()
end sub

' --- OAuth Flow ---
sub getDeviceCode()
    url = "https://api.dropboxapi.com/oauth2/device/authorize"
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url)
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    
    params = "client_id=" + m.appKey
    response = xfer.PostFromString(params)
    
    if response <> "" then
        json = ParseJson(response)
        if json <> invalid then
            m.top.authResult = json
            pollForToken(json.device_code, json.interval)
        end if
    end if
end sub

sub pollForToken(deviceCode as string, interval as integer)
    url = "https://api.dropboxapi.com/oauth2/token"
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url)
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    
    params = "grant_type=urn:ietf:params:oauth:grant-type:device_code"
    params += "&client_id=" + m.appKey
    params += "&device_code=" + deviceCode
    
    while true
        response = xfer.PostFromString(params)
        if response <> "" then
            json = ParseJson(response)
            if json <> invalid then
                if json.access_token <> invalid then
                    saveTokens(json)
                    m.top.status = "SUCCESS"
                    return
                else if json.error <> "authorization_pending" then
                    m.top.status = "ERROR"
                    return
                end if
            end if
        end if
        sleep(interval * 1000)
    end while
end sub

' --- Data Fetching ---
sub fetchDropboxPhotos()
    if m.accessToken = invalid then return
    cfg = GetConfig()
    url = "https://api.dropboxapi.com/2/files/list_folder"
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url) : xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.AddHeader("Authorization", "Bearer " + m.accessToken)
    xfer.AddHeader("Content-Type", "application/json")
    body = { "path": cfg.slideshow.folderName, "recursive": false }
    response = xfer.PostFromString(FormatJson(body))
    if response <> "" then
        json = ParseJson(response)
        if json <> invalid and json.entries <> invalid then
            urls = []
            for each entry in json.entries
                if entry[".tag"] = "file" then
                    link = getTemporaryLink(entry.path_lower)
                    if link <> "" then urls.push(link)
                end if
            end for
            m.top.photoUrls = urls
        end if
    end if
end sub

function getTemporaryLink(path as string) as string
    url = "https://api.dropboxapi.com/2/files/get_temporary_link"
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url) : xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.AddHeader("Authorization", "Bearer " + m.accessToken)
    xfer.AddHeader("Content-Type", "application/json")
    body = { "path": path }
    response = xfer.PostFromString(FormatJson(body))
    if response <> "" then
        json = ParseJson(response)
        if json <> invalid then return json.link
    end if
    return ""
end function
