sub init()
    m.top.functionName = "runTask"
    cfg = GetConfig()
    m.appKey = cfg.dropbox.appKey
    m.appSecret = cfg.dropbox.appSecret
    m.initialAuthCode = cfg.dropbox.initialAuthCode
end sub

sub runTask()
    hasTokens = loadSavedTokens()
    m.port = CreateObject("roMessagePort")
    m.top.observeField("status", m.port)
    
    if hasTokens then
        print "[DropboxTask] Tokens found on startup, setting status SUCCESS"
        m.top.status = "SUCCESS"
    else if m.initialAuthCode <> invalid and m.initialAuthCode <> "" and m.initialAuthCode <> "YOUR_CODE_HERE" then
        print "[DropboxTask] Found initialAuthCode in config, exchanging..."
        if exchangeCodeForTokens(m.initialAuthCode) then
            m.top.status = "SUCCESS"
        else
            print "[DropboxTask] Initial code exchange failed, falling back to AUTHENTICATE"
            m.top.status = "AUTHENTICATE"
            handleStatus("AUTHENTICATE")
        end if
    else
        print "[DropboxTask] No tokens or code found, waiting for AUTHENTICATE"
        handleStatus(m.top.status)
    end if

    while true
        ' Use 1 second timeout to avoid busy-wait
        msg = wait(1000, m.port)
        if type(msg) = "roSGNodeEvent" then
            if msg.getField() = "status" then
                handleStatus(msg.getData())
            end if
        else if msg = invalid then
            ' Occasional sleep to give other threads time
            sleep(100)
        end if
    end while
end sub

sub handleStatus(status as string)
    print "[DropboxTask] Handle Status: "; status
    if status = "AUTHENTICATE" then
        getDeviceCode()
    else if status = "FETCH_PHOTOS" or status = "REFRESH_PHOTOS" then
        if m.accessToken <> invalid and m.accessToken <> "" then
            fetchDropboxPhotoList()
        else if refreshAccessToken() then
            fetchDropboxPhotoList()
        else
            print "[DropboxTask] Token missing and refresh failed, re-authenticating"
            m.top.status = "AUTHENTICATE"
        end if
    else if Left(status, 12) = "GET_LINK_FOR" then
        parts = status.split("|")
        if parts.count() > 1 then
            path = parts[1]
            getFreshLink(path)
        end if
    end if
end sub

function loadSavedTokens() as boolean
    sec = CreateObject("roRegistrySection", "Authentication")
    if sec.Exists("db_refresh_token") then
        m.refreshToken = sec.Read("db_refresh_token")
        m.accessToken = sec.Read("db_access_token")
        return true
    end if
    
    ' Check config for hardcoded refresh token
    cfg = GetConfig()
    if cfg.dropbox.refreshToken <> invalid and cfg.dropbox.refreshToken <> "" then
        m.refreshToken = cfg.dropbox.refreshToken
        print "[DropboxTask] Found hardcoded refresh token in config"
        return true
    end if
    
    return false
end function

sub saveTokens(json as object)
    sec = CreateObject("roRegistrySection", "Authentication")
    if json.refresh_token <> invalid then 
        m.refreshToken = json.refresh_token
        sec.Write("db_refresh_token", json.refresh_token)
        print "[DropboxTask] Saved new refresh token"
    end if
    if json.access_token <> invalid then 
        m.accessToken = json.access_token
        sec.Write("db_access_token", json.access_token)
        print "[DropboxTask] Saved new access token"
    end if
    sec.Flush()
end sub

function exchangeCodeForTokens(code as string) as boolean
    print "[DropboxTask] Exchanging code for tokens..."
    url = "https://api.dropboxapi.com/oauth2/token"
    
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url)
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.AddHeader("Content-Type", "application/x-www-form-urlencoded")
    
    params = "code=" + xfer.UrlEncode(code)
    params += "&grant_type=authorization_code"
    params += "&client_id=" + xfer.UrlEncode(m.appKey)
    params += "&client_secret=" + xfer.UrlEncode(m.appSecret)
    
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    if xfer.AsyncPostFromString(params) then
        msg = wait(10000, port)
        if type(msg) = "roUrlEvent" then
            respCode = msg.GetResponseCode()
            respBody = msg.GetString()
            print "[DropboxTask] Exchange response code: "; respCode
            if respCode = 200 then
                json = ParseJson(respBody)
                if json <> invalid and json.access_token <> invalid then
                    saveTokens(json)
                    return true
                else
                    print "[DropboxTask] Exchange error: Invalid JSON or missing access_token"
                end if
            else
                print "[DropboxTask] Exchange Error ("; respCode; "): "; respBody
            end if
        end if
    end if
    return false
end function

function refreshAccessToken() as boolean
    if m.refreshToken = invalid then 
        print "[DropboxTask] No refresh token available"
        return false
    end if
    
    print "[DropboxTask] Refreshing access token..."
    url = "https://api.dropboxapi.com/oauth2/token"
    
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url)
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.AddHeader("Content-Type", "application/x-www-form-urlencoded")
    
    params = "grant_type=refresh_token"
    params += "&client_id=" + xfer.UrlEncode(m.appKey)
    params += "&client_secret=" + xfer.UrlEncode(m.appSecret)
    params += "&refresh_token=" + xfer.UrlEncode(m.refreshToken)
    
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    if xfer.AsyncPostFromString(params) then
        msg = wait(10000, port)
        if type(msg) = "roUrlEvent" then
            code = msg.GetResponseCode()
            print "[DropboxTask] Refresh response code: "; code
            if code = 200 then
                body = msg.GetString()
                if body <> "" then
                    json = ParseJson(body)
                    if json <> invalid and json.access_token <> invalid then
                        saveTokens(json)
                        return true
                    end if
                end if
            else
                print "[DropboxTask] Refresh Error: "; msg.GetString()
            end if
        end if
    end if
    return false
end function

sub getDeviceCode()
    print "[DropboxTask] Requesting device code..."
    url = "https://api.dropboxapi.com/oauth2/device/authorize"
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url)
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.AddHeader("Content-Type", "application/x-www-form-urlencoded")
    
    params = "client_id=" + m.appKey
    
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    if xfer.AsyncPostFromString(params) then
        msg = wait(10000, port)
        if type(msg) = "roUrlEvent" then
            code = msg.GetResponseCode()
            body = msg.GetString()
            print "[DropboxTask] Device code response: "; code; " : "; body
            if code = 200 and body <> "" then
                json = ParseJson(body)
                if json <> invalid then
                    print "[DropboxTask] Device code received: "; json.user_code
                    m.top.authResult = json
                    pollForToken(json.device_code, json.interval)
                end if
            else
                print "[DropboxTask] Device code error: "; code; " : "; body
                m.top.status = "DB_AUTH_ERR_" + StrI(code).Trim()
            end if
        end if
    end if
end sub

sub pollForToken(deviceCode as string, interval as integer)
    print "[DropboxTask] Polling for token..."
    url = "https://api.dropboxapi.com/oauth2/token"
    params = "grant_type=urn:ietf:params:oauth:grant-type:device_code&client_id=" + m.appKey + "&device_code=" + deviceCode
    while true
        xfer = CreateObject("roUrlTransfer")
        xfer.SetUrl(url)
        xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
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
                        print "[DropboxTask] Token received successfully"
                        saveTokens(json)
                        m.top.status = "SUCCESS"
                        return
                    else if json <> invalid and json.error <> "authorization_pending" then
                        print "[DropboxTask] Token polling error: "; json.error
                        m.top.status = "DB_TOKEN_ERR_" + json.error
                        return
                    else
                        print "[DropboxTask] Still waiting for user authorization..."
                    end if
                end if
            end if
        end if
        sleep(interval * 1000)
    end while
end sub

sub fetchDropboxPhotoList()
    if m.accessToken = invalid then 
        print "[DropboxTask] No access token for fetch"
        m.top.status = "DB_FETCH_NO_TOKEN"
        return
    end if
    cfg = GetConfig()
    path = cfg.slideshow.folderName
    if path = "" or path = "/" then 
        path = "" 
    else
        if Left(path, 1) <> "/" then 
            path = "/" + path
        end if
        if Right(path, 1) = "/" then 
            path = Left(path, Len(path) - 1)
        end if
    end if
    
    print "[DropboxTask] Listing folder: '"; path; "'"
    url = "https://api.dropboxapi.com/2/files/list_folder"
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url)
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.AddHeader("Authorization", "Bearer " + m.accessToken)
    xfer.AddHeader("Content-Type", "application/json")
    
    body = { "path": path, "recursive": false }
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    if xfer.AsyncPostFromString(FormatJson(body)) then
        msg = wait(10000, port)
        if type(msg) = "roUrlEvent" then
            code = msg.GetResponseCode()
            resp = msg.GetString()
            print "[DropboxTask] List folder response code: "; code
            if code = 200 then
                json = ParseJson(resp)
                if json <> invalid and json.entries <> invalid then
                    paths = []
                    print "[DropboxTask] Total entries found: "; json.entries.count()
                    for each entry in json.entries
                        fname = LCase(entry.name)
                        tag = entry[".tag"]
                        print "[DropboxTask] Found entry: "; entry.name; " ("; tag; ")"
                        if tag = "file" and (InStr(1, fname, ".jpg") >= 1 or InStr(1, fname, ".png") >= 1 or InStr(1, fname, ".jpeg") >= 1) then
                            paths.push(entry.path_lower)
                        end if
                    end for
                    print "[DropboxTask] Found "; paths.count(); " valid photos"
                    m.top.status = "DB_LIST_OK"
                    m.top.photoUrls = paths
                else
                    m.top.status = "DB_LIST_ERR_PARSE"
                    print "[DropboxTask] Error parsing JSON or missing entries"
                end if
            else if code = 401 then
                print "[DropboxTask] Unauthorized (401), clearing tokens and re-authenticating"
                sec = CreateObject("roRegistrySection", "Authentication")
                sec.Delete("db_access_token")
                sec.Delete("db_refresh_token")
                sec.Flush()
                m.accessToken = ""
                m.refreshToken = ""
                m.top.status = "AUTHENTICATE"
                handleStatus("AUTHENTICATE")
            else
                m.top.status = "DB_LIST_ERR_" + ("" + code)
                print "[DropboxTask] List folder error ("; code; "): "; resp
            end if
        end if
    end if
end sub

sub getFreshLink(path as string)
    print "[DropboxTask] Getting fresh link for: "; path
    url = "https://api.dropboxapi.com/2/files/get_temporary_link"
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url)
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.AddHeader("Authorization", "Bearer " + m.accessToken)
    xfer.AddHeader("Content-Type", "application/json")
    body = { "path": path }
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    if xfer.AsyncPostFromString(FormatJson(body)) then
        msg = wait(5000, port)
        if type(msg) = "roUrlEvent" then
            code = msg.GetResponseCode()
            print "[DropboxTask] Get link response code: "; code
            if code = 200 then
                json = ParseJson(msg.GetString())
                if json <> invalid then
                    print "[DropboxTask] Link ready: "; Left(json.link, 50); "..."
                    m.top.status = "DB_LINK_READY"
                    m.top.photoUrls = [json.link]
                end if
            else
                print "[DropboxTask] Get link error: "; msg.GetString()
            end if
        end if
    end if
end sub
