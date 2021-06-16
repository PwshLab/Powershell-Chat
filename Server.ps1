function Start-Server {
    Param (
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [int64]
        $port = 9000,

        [Parameter(Position = 1)]
        [ValidateNotNullOrEmpty()]
        [int64]
        $processTimeout = 120
    )


    Write-Host
    Write-Host
    Write-Host Starting Server...

    $endpoint = new-object System.Net.IPEndPoint ([system.net.ipaddress]::any, $port)
    $listener = new-object System.Net.Sockets.TcpListener $endpoint
    $listener.start()

    while ($true) {

        Write-Host Waiting For Connection...
        Write-Host

        $client = $listener.AcceptTcpClient()
        $stream = $client.GetStream()

        $timeout = [Text.Encoding]::ASCII.GetBytes([String]$processTimeout)
        $timepad = New-Object byte[] (2048-$timeout.Length)
        $timebytes = $timeout + $timepad
        $stream.Write($timebytes, 0, $timebytes.Length)

        Write-Host Connected
        Write-Host
        Write-Host Simple Shell to Remote PC
        Write-Host

        while ($client.Connected) {
            Write-Host -NoNewline '> '
            $command = $Host.UI.ReadLine()

            $commandBytes = [System.Text.Encoding]::Unicode.GetBytes($command)
            $commandLength = [System.Text.Encoding]::ASCII.GetBytes([String]$commandBytes.Length)
            $pad = New-Object byte[] (2048-$commandLength.Length)
            $l = $commandLength + $pad
            $stream.Write($l, 0, $l.Length) | Out-Null
            $stream.Write($commandBytes, 0, $commandBytes.Length) | Out-Null
            $outputLength = New-Object byte[] 2048
            $stream.Read($outputLength, 0, $outputLength.Length) | Out-Null
            0..([int64]($outputLength.Length)-1) | ForEach-Object {if ($outputLength[$_] -ne 0){$outputSize+=[text.encoding]::ASCII.GetString($outputLength[$_])}}
            $output = New-Object byte[] ([int64]$outputSize)
            $stream.Read($output, 0, $output.Length) | Out-Null
            $outputString = [Text.Encoding]::Unicode.GetString($output)
            Write-Host "$outputString"
            $command = $commandBytes = $commandLength = $pad = $l = $outputLength = $outputSize = $output = $outputString = $null
            [GC]::Collect()
        }
        Write-Host Client Disconnected
        Write-Host
    }
}