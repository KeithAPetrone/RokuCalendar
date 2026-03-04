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
        fetchDropboxPhotos()
    end if
end sub

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
        if type(msg) = "roUrlEvent" then
            if msg.GetResponseCode() = 200 then
                body = msg.GetString()
                if body <> "" then
                    json = ParseJson(body)
                    if json <> invalid then
                        m.top.authResult = json
                        pollForToken(json.device_code, json.interval)
                    end if
                end if
            else
                m.top.status = "DB_AUTH_ERR_" + msg.GetResponseCode().toStr()
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

sub fetchDropboxPhotos()
    if m.accessToken = invalid then 
        m.top.status = "DB_FETCH_NO_TOKEN"
        return
    end if
    cfg = GetConfig()
    url = "https://api.dropboxapi.com/2/files/list_folder"
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url) : xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.AddHeader("Authorization", "Bearer " + m.accessToken)
    xfer.AddHeader("Content-Type", "application/json")
    body = { "path": cfg.slideshow.folderName, "recursive": false }
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    if xfer.AsyncPostFromString(FormatJson(body)) then
        msg = wait(10000, port)
        if type(msg) = "roUrlEvent" then
            code = msg.GetResponseCode()
            if code = 200 then
                body = msg.GetString()
                if body <> "" then
                    json = ParseJson(body)
                    if json <> invalid and json.entries <> invalid then
                        urls = []
                        for each entry in json.entries
                            if entry[".tag"] = "file" then
                                link = getTemporaryLink(entry.path_lower)
                                if link <> "" then urls.push(link)
                            end if
                        end for
                        if urls.count() > 0 then
                            m.top.photoUrls = urls
                            m.top.status = "DB_FETCH_OK_" + urls.count().toStr()
                        else
                            m.top.status = "DB_FETCH_EMPTY"
                        end if
                    end if
                end if
            else
                m.top.status = "DB_FETCH_ERR_" + code.toStr()
            end if
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
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    if xfer.AsyncPostFromString(FormatJson(body)) then
        msg = wait(5000, port)
        if type(msg) = "roUrlEvent" and msg.GetResponseCode() = 200 then
            body = msg.GetString()
            if body <> "" then
                json = ParseJson(body)
                if json <> invalid then return json.link
            end if
        end if
    end if
    return ""
end function
