sub Main()
    print "Starting RokuCalendar"
    
    ' Attempt to disable screensaver on main thread
    deviceInfo = CreateObject("roDeviceInfo")
    try
        deviceInfo.EnableScreensaver(false)
    catch e
        print "EnableScreensaver not supported or failed: "; e.message
    end try
    
    port = CreateObject("roMessagePort")
    screen = CreateObject("roSGScreen")
    screen.SetMessagePort(port)
    
    scene = screen.CreateScene("HelloScene")
    screen.Show()
    
    print "Scene displayed"
    
    while true
        msg = wait(0, port)
        if type(msg) = "roSGScreenEvent" then
            if msg.isScreenClosed() then
                return
            end if
        end if
    end while
end sub
