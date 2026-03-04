sub init()
    m.top.functionName = "runTask"
    cfg = GetConfig()
    m.appKey = cfg.dropbox.appKey
end sub

sub runTask()
    loadSavedTokens()
    m.port = CreateObject("roMessagePort")
    m.top.observeField("status", m.port)
    handleStatus(m.top.status)
    while true
        msg = wait(0, m.port)
        if type(msg) = "roSGNodeEvent" and msg.getField() = "status" then
            handleStatus(msg.getData())
        end if
    end while
end sub

sub handleStatus(status as string)
    if status = "AUTHENTICATE" then
        getDeviceCode()
    else if status = "FETCH_PHOTOS" then
        fetchDropboxPhotoList()
    else if status.left(11) = "GET_LINK_FOR" then
        path = status.split("|")[1]
        getFreshLink(path)
    end if
end sub

' --- Persistence ---
function loadSavedTokens() as boolean
    sec = CreateObject("roRegistrySection", "Authentication")
    if sec.Exists("db_refresh_token") then
        m.refreshToken = sec.Read("db_refresh_token")
        m.accessToken = sec.Read("db_access_token")
        m.top.status = "SUCCESS" 
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
        sec.Write("db_access_token", json.access_token)
    end if
    sec.Flush()
end sub

' --- OAuth Flow ---
sub getDeviceCode()
    url = "https://api.dropboxapi.com/oauth2/device/authorize"
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url) : xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.AddHeader("Content-Type", "application/x-www-form-urlencoded")
    params = "client_id=" + m.appKey
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    if xfer.AsyncPostFromString(params) then
        msg = wait(10000, port)
        if type(msg) = "roUrlEvent" and msg.GetResponseCode() = 200 then
            body = msg.GetString()
            if body <> "" then
                json = ParseJson(body)
                if json <> invalid then
                    m.top.authResult = json
                    pollForToken(json.device_code, json.interval)
                end if
            end if
        end if
    end if
end sub

sub pollForToken(deviceCode as string, interval as integer)
    url = "https://api.dropboxapi.com/oauth2/token"
    params = "grant_type=urn:ietf:params:oauth:grant-type:device_code&client_id=" + m.appKey + "&device_code=" + deviceCode
    while true
        xfer = CreateObject("roUrlTransfer")
        xfer.SetUrl(url) : xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
        xfer.AddHeader("Content-Type", "application/x-www-form-urlencoded")
        port = CreateObject("roMessagePort")
        xfer.SetMessagePort(port)
        if xfer.AsyncPostFromString(params) then
            msg = wait(10000, port)
            if type(msg) = "roUrlEvent" then
                code = msg.GetResponseCode()
                body = msg.GetString()
                if body <> "" then
                    json = ParseJson(body)
                    if code = 200 and json <> invalid and json.access_token <> invalid then
                        saveTokens(json)
                        m.top.status = "SUCCESS"
                        return
                    else if json <> invalid and json.error <> "authorization_pending" then
                        m.top.status = "DB_TOKEN_ERR_" + json.error
                        return
                    end if
                end if
            end if
        end if
        sleep(interval * 1000)
    end while
end sub

' --- Data Fetching ---
sub fetchDropboxPhotoList()
    if m.accessToken = invalid then return
    cfg = GetConfig()
    path = cfg.slideshow.folderName
    if path.left(1) <> "/" then path = "/" + path
    
    url = "https://api.dropboxapi.com/2/files/list_folder"
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url) : xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.AddHeader("Authorization", "Bearer " + m.accessToken)
    xfer.AddHeader("Content-Type", "application/json")
    
    body = { "path": path, "recursive": false }
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    if xfer.AsyncPostFromString(FormatJson(body)) then
        msg = wait(10000, port)
        if type(msg) = "roUrlEvent" and msg.GetResponseCode() = 200 then
            json = ParseJson(msg.GetString())
            if json <> invalid and json.entries <> invalid then
                paths = []
                for each entry in json.entries
                    fname = entry.name.toLower()
                    if entry[".tag"] = "file" and (fname.instr(".jpg") >= 0 or fname.instr(".png") >= 0 or fname.instr(".jpeg") >= 0) then
                        paths.push(entry.path_lower)
                    end if
                end for
                ' Return the list of PATHS instead of LINKS
                m.top.photoUrls = paths
                m.top.status = "DB_LIST_OK_" + paths.count().toStr()
            end if
        end if
    end if
end sub

sub getFreshLink(path as string)
    url = "https://api.dropboxapi.com/2/files/get_temporary_link"
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url) : xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.AddHeader("Authorization", "Bearer " + m.accessToken)
    xfer.AddHeader("Content-Type", "application/json")
    body = { "path": path }
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    if xfer.AsyncPostFromString(FormatJson(body)) then
        msg = wait(5000, port)
        if type(msg) = "roUrlEvent" and msg.GetResponseCode() = 200 then
            json = ParseJson(msg.GetString())
            if json <> invalid then
                ' We update the photoUrls array with JUST THIS ONE fresh link
                ' so HelloScene can pick it up
                m.top.photoUrls = [json.link]
                m.top.status = "DB_LINK_READY"
            end if
        end if
    end if
end sub
