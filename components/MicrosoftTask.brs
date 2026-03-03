sub init()
    m.top.functionName = "execute"
    ' You will need to replace this with a real Client ID from the 
    ' Microsoft Entra admin center (Azure AD portal)
    m.clientId = "YOUR_MICROSOFT_CLIENT_ID_HERE"
    m.tenantId = "common"
end sub

sub execute()
    if m.top.status = "AUTHENTICATE" then
        getDeviceCode()
    else if m.top.status = "FETCH_PHOTOS" then
        fetchOneDrivePhotos()
    end if
end sub

sub getDeviceCode()
    url = "https://login.microsoftonline.com/" + m.tenantId + "/oauth2/v2.0/devicecode"
    
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url)
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.AddHeader("Content-Type", "application/x-www-form-urlencoded")
    
    params = "client_id=" + m.clientId + "&scope=Files.Read%20User.Read%20offline_access"
    response = xfer.PostFromString(params)
    
    if response <> "" then
        json = ParseJson(response)
        if json <> invalid then
            ' This is where the app will show the code to the user
            m.top.authResult = json
            pollForToken(json.device_code, json.interval)
        end if
    end if
end sub

sub pollForToken(deviceCode as string, interval as integer)
    url = "https://login.microsoftonline.com/" + m.tenantId + "/oauth2/v2.0/token"
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url)
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.AddHeader("Content-Type", "application/x-www-form-urlencoded")
    
    params = "grant_type=urn:ietf:params:oauth:grant-type:device_code"
    params += "&client_id=" + m.clientId
    params += "&device_code=" + deviceCode
    
    while true
        response = xfer.PostFromString(params)
        if response <> "" then
            json = ParseJson(response)
            if json <> invalid then
                if json.access_token <> invalid then
                    ' Success! Save the token
                    m.top.authResult = json
                    m.top.status = "SUCCESS"
                    return
                else if json.error <> "authorization_pending" then
                    ' Some other error happened
                    m.top.status = "ERROR"
                    return
                end if
            end if
        end if
        sleep(interval * 1000)
    end while
end sub

sub fetchOneDrivePhotos()
    ' Logic for listing files from a specific folder 
    ' would go here after successful authentication.
end sub
