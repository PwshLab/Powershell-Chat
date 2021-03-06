function Start-ChatServer {
    [CmdletBinding()]
    param (
        [Parameter()]
        [Int64]
        $Port = 8999
    )

    $ErrorActionPreference = "SilentlyContinue"

    $Endpoint = new-object System.Net.IPEndPoint ([system.net.ipaddress]::any, $Port)
    $Listener = new-object System.Net.Sockets.TcpListener $Endpoint
    $Listener.start()
    $ClientList = [System.Collections.ArrayList]@()
    $ClientCallback = $Listener.AcceptTcpClientAsync()
    
    Start-ChatServerBeacon

    while ($Listener.Server.IsBound) {
        if ($ClientCallback.IsCompleted) {
            $Client = $ClientCallback.Result
            $Stream = $Client.GetStream()
            $ClientObj = [PSCustomObject]@{"Client" = $Client; "Stream" = $Stream}
            $ClientList.Add($ClientObj) | Out-Null
            $ClientCallback = $Listener.AcceptTcpClientAsync()
        }

        $ToRemove = [System.Collections.ArrayList]@()
        for ($i = 0; $i -lt $ClientList.Count; $i++) {
            if (-not $ClientList.Item($i).Client.Connected) {
                $ToRemove.Add($i)
            } elseif (-not $ClientList.Item($i).Stream.CanWrite) {
                $ToRemove.Add($i)
            }
        }
        for ($i = 0; $i -lt $ToRemove.Count; $i++) {
            $ClientList.RemoveAt($ToRemove.Item($i))
        }

        for ($i = 0; $i -lt $ClientList.Count; $i++) {
            if ($ClientList.Item($i).Stream.DataAvailable) {
                $Data = New-Object byte[] 1024
                $ClientList.Item($i).Stream.Read($Data, 0, $Data.Length) | Out-Null
                for ($j = 0; $j -lt $ClientList.Count; $j++) {
                    if ($ClientList.Item($j).Stream.CanWrite) {
                        $ClientList.Item($j).Stream.Write($Data, 0, $Data.Length) | Out-Null
                    }
                }
            }
        }
    }

    $Listener.Stop()
}

function Start-ChatClient {
    [CmdletBinding()]
    param (
        [Parameter()]
        [Int64]
        $Port = 8999,
        [Parameter(Mandatory=$false)]
        [String]
        $IP
    )

    $Name = Read-Host -Prompt "Username "
    $Name = $Name.Replace('"', '').Replace("'", "")

    Clear-Host
    
    if (-not $IP) {
        Write-Host -Object "Searching for local chat servers....."
        $IP = Start-LocalPortscan -Port 8998 | Where-Object -Property "Open" -Value $true -EQ | Select-Object -ExpandProperty "IPAddress" -First 1
        
        if (-not $IP) {Write-Host -Object ""; Write-Host "No servers found."; Start-Sleep -Seconds 2; Exit}
    }
    
    Write-Host -Object "Connecting to chat server....."

    $Client = New-Object System.Net.Sockets.TcpClient $IP, $Port
    
    if ((-not $Client) -or (-not $Client.Connected)) {Write-Host -Object ""; Write-Host "Connection failed."; Start-Sleep -Seconds 2; Exit}
    
    $Stream = $Client.GetStream()

    Clear-Host
    Write-Host -Object "---------------------------Message History---------------------------"

    $Prompt = "$Name> "
    $FilePath = Join-Path -Path	$env:TMP -ChildPath "/"
    $ScriptBlock = {Param($Prompt,$FilePath,$ParentId) ;$FilePath =  Join-Path -Path $FilePath -ChildPath "/$PID.txt"; [console]::WindowWidth=75; [console]::WindowHeight=20; Clear-Host; Write-Host -Object "---------Nachrichten-in-dieses-Fenster-Schreiben---------"; Write-Host -Object "$null"; while ((Get-Process -Id $ParentId -ErrorAction SilentlyContinue)) {Write-Host -Object $Prompt -NoNewline; $Host.UI.ReadLine() | Out-File -FilePath $FilePath}; Remove-Item -Path $FilePath -Force -ErrorAction SilentlyContinue}
    $Arg = "'$Prompt','$FilePath','$PID'"
    $ID = (Start-Process powershell -ArgumentList "-Command Invoke-Command -ScriptBlock {$ScriptBlock} -Argumentlist $Arg" -PassThru).Id
    $FilePath = Join-Path -Path	$env:TMP -ChildPath "/$ID.txt"

    while ($Client.Connected) {
        if ($Stream.DataAvailable) {
            $DataA = New-Object byte[] 1024
            $Read = $Stream.Read($DataA, 0, $DataA.Length)
            $DataB = New-Object byte[] $Read
            $DataA[0..($Read-1)].CopyTo($DataB, 0)
            if ($DataB.Length -gt 0) {
                $InMessage = [Text.Encoding]::Unicode.GetString($DataB)
                $InMessageFull += $InMessage
                $InMessage = $null
            }
        } else {
            if ($InMessageFull.Length -gt 0) {
                $InMessageFull = $InMessageFull.Substring(0, [Math]::Min([Console]::BufferWidth, $InMessageFull.Length))
                Write-Host $InMessageFull
                $InMessageFull = $null
            }
        }
        if (Test-Path $FilePath -ErrorAction SilentlyContinue) {
            Start-Sleep -Milliseconds 50
            $OutMessage = Get-Content -Path $FilePath
            Remove-Item -Path $FilePath -Force
            if ($OutMessage) {
                $OutMessage = $OutMessage.Replace('"', '').Replace("'", "")
                $OutMessage = "$Name> $OutMessage"
                $Data = [Text.Encoding]::Unicode.GetBytes($OutMessage)
                $Stream.Write($Data, 0, $Data.Length)
            }
        }
        if (-not (Get-Process -Id $ID -ErrorAction SilentlyContinue)) {
            $ID = (Start-Process powershell -ArgumentList "-Command Invoke-Command -ScriptBlock {$ScriptBlock} -Argumentlist $Arg" -PassThru).Id
            $FilePath = Join-Path -Path	$env:TMP -ChildPath "/$ID.txt"
        }
    }
}

function Start-ChatServerBeacon {
    [CmdletBinding()]
    param (
        [Parameter()]
        [Int64]
        $Port = 8998
    )
    $ScriptBlock = {
        param ($Port)
        $Endpoint = new-object System.Net.IPEndPoint ([system.net.ipaddress]::any, $Port)
        $Listener = new-object System.Net.Sockets.TcpListener $Endpoint
        $Listener.start()
        while ($Listener.Server.IsBound) {
            $AsyncAccept = $Listener.BeginAcceptTcpClient($null,$null)
            while (-not $AsyncAccept.IsCompleted) {Start-Sleep -Milliseconds 10}
        }
    }
    Start-Job -ScriptBlock $ScriptBlock -ArgumentList @($Port) | Out-Null
}

function Get-LocalIP {
    $IP = Get-NetIPAddress | Where-Object -Property "PrefixOrigin" -Value "Dhcp" -EQ | Select-Object -ExpandProperty "IPAddress" -First 1
    Write-Output $IP
}

function Start-TestPort {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Int64]
        $Port,
        [Parameter(Mandatory = $true)]
        [String]
        $IP
    )

        $RequestCallback = $State = $null
        $Client = New-Object System.Net.Sockets.TcpClient
        $BeginConnect = $client.BeginConnect($IP,$Port,$RequestCallback,$State)
        Start-Sleep -Milliseconds 100
        $Connected = $Client.Connected
        $Client.Close()
        Write-Output $Connected
}

function Start-LocalPortscan {
    [CmdletBinding()]
    param (
        [Parameter()]
        [Int64]
        $Port
    )

    $SourceIP = Get-LocalIP
    $SubnetIP = ($SourceIP.Split(".") | Select-Object -First 3) -Join "."

    for ($i = 1; $i -lt 256; $i++) {
        $TestIP = $SubnetIP + "." + [String]$i
        $State = Start-TestPort -Port $Port -IP $TestIP
        $Result = [PSCustomObject]@{ "IPAddress" = $TestIP; "Port" = $Port; "Open" = $State }
        Write-Output $Result
    }
}
