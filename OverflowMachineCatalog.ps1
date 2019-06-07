<#

	OverflowMachineCatalog.ps1

.Synopsis
   Short description:
   This scripts give the possibility to have 1 DeliveryGroup with 2 MachineCatalogs and User are getting VDIs
   from one MachineCataog until it's full ant then users receive VDIs from other Catalog.. 

.DESCRIPTION

   Long description:      

   This script gives the possibility to have 1 DeliveryGroup with 2 MachineCatalogs and User are getting machines 
   from one MachineCataog until it's full ant then users receive machines from other catalog.

   Example UseCase: #1: MachineCatalog1 has VDIs with GPUs and MachineCatalog2 cheaper VDIs without GPUs. 
                    #2: MachineCatalog1 has machines On-Prem and MachineCatalog2 in Cloud. 
					
	The provided Desktop/App must be restricted to machines with the Tag : "availibleForUsers"

    Important! All Maschines in MachineCatalog must be Member of DeliveryGroup or set to MaintenanceMode as the Count goes to MC.
    More infos here: http://blog.sachathomet.ch/de/2019/06/08/machinecatalog-with-overflow/
   
.EXAMPLE
   Example of how to use this cmdlet

   launch OverflowMachineCatalog.ps1 every 5 minutes

   via Scheduled Task: powershell.exe -NoProfile -file .\OverflowMachineCatalog.ps1

#>

<#
OverflowMachineCatalog.ps1 

V0.1 5.12.2018 Sacha Thomet
V0.2 10.12.2018 Sacha Thomet : Maschines provided now with Tag "availibleForUsers" instead of Non- MaintMode 
V0.3 13.12.2018 Sacha Thomet : Make reconnect possible when activate "Soft-Maintenance-Mode" with not remove Tag AvailibleForUsers on Maschines with connected Users 
V0.4 14.12.2018 Sacha Thomet : added $MaxRecordCount


#>

#This block cannot be in a function as he is responsible to find the Script path 
$currentDir = Split-Path $MyInvocation.MyCommand.Path
$outputpath = Join-Path $currentDir "" #add here a custom output folder if you wont have it on the same directory
$outputdate = Get-Date -Format 'yyyyMMddHHmm'
$outputdateShort = Get-Date -Format 'yyyyMMdd'
$logfile = Join-Path $outputpath ("Spillover_$outputdateShort.log")

#This block ist for defined variables
$MaxRecordCount = 1000 #this number must be at least the number of desktops in the farm, otherweise the script cannot get all records
$MC1 = "MC-XD-GPU" #MC1 = Machine Catalog which is prefered and used until full
$MC2 = "MC-XD-NoGPU" #MC2 = Maschine Catalog which is NOT prefered and used only when MC1 is full 
$FreeMachineThreshold = 5 #minimum free machines in MachineCatalog1 - depends of size of environment and how heavy is a logon storm 
$PurposeMC1 = "VDIs with GPU" #define what is special on MachineCatalog1



#Don't change below here if you don't know what you are doing ... 
#==============================================================================================
# Load only the snap-ins, which are used
if ((Get-PSSnapin "Citrix.*" -EA silentlycontinue) -eq $null) {
try { Add-PSSnapin Citrix.* -ErrorAction Stop }
catch { write-error "Error Get-PSSnapin Citrix.Broker.Admin.* Powershell snapin"; Return }
}



function CheckFreeVDIsMC1() {
$Mc1Destkops = Get-BrokerMachine -MaxRecordCount $MaxRecordCount | where {$_.CatalogName -eq $global:MC1 -AND $_.SessionCount -eq "0" -AND $_.InMaintenanceMode -eq $false -AND $_.RegistrationState -eq "Registered"} 

$freeMC1Desktops = $Mc1Destkops.count
"Free machines in '$MC1': '$freeMC1Desktops' "  | LogMe -display -progress




#If $Mc1Destkops.count ist greater or equal "$FreeMachineThreshold" call function RemoveAvailibleForUsers
 if ($Mc1Destkops.count -ge $global:FreeMachineThreshold) {
 
		"call function RemoveAvailibleForUsers to only provide: $global:PurposeMC1 " | LogMe -display -progress
 
        RemoveAvailibleForUsers
    }

#If $Mc1Destkops.count is lower than "$FreeMachineThreshold" call function AddAvailibleForUsers
elseif ($Mc1Destkops.count -lt $global:FreeMachineThreshold) {

		"call function AddAvailibleForUsers to temporary NOT provide: '$global:PurposeMC1' " | LogMe -display -progress

		AddAvailibleForUsers
    }



}

function RemoveAvailibleForUsers() {
#this function removes the Tag "availibleForUsers" to machines in $MC2 (similiar like a soft maintenance mode) - except thos with sessions on it! To make reconnect possible! 
"start function Remove-availibleForUsers, all machines in '$MC2' will set to Soft-Maint-Mode - reconnect possible!" | LogMe -display -progress

$Mc2Desktops = Get-BrokerMachine -MaxRecordCount $MaxRecordCount | where {$_.CatalogName -eq $global:MC2 -AND $_.SessionCount -eq "0"}


foreach ($machine in $Mc2Desktops) {
   
  Remove-BrokerTag -Name 'availibleForUsers' -Machine $machine.MachineName 
   
 }

}

function AddAvailibleForUsers() {
#this function Add the Tag availibleForUsers to all machines in $MC2
"start function AddAvailibleForUsers, all machines in '$MC2' will REMOVED from Soft-Maint-Mode (Add Tag:availibleForUsers)" | LogMe -display -progress

$Mc2Desktops = Get-BrokerMachine  -MaxRecordCount $MaxRecordCount | where {$_.CatalogName -eq $global:MC2}


foreach ($machine in $Mc2Desktops) {
   
  Add-BrokerTag -Name 'availibleForUsers' -Machine $machine.MachineName 
   
 }

}



function LogMe() {
    # This function is for logging (Output on the shell in 3 colors and write in a logfile)
    # just use it with a Pipe after a command to put in the result
    # eg. | LogMe -display -progress

    Param(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)] $logEntry,
        [switch]$display,
        [switch]$error,
        [switch]$warning,
        [switch]$progress
    )
 
    if ($error) {
        $logEntry = "[ERROR] $logEntry" ; Write-Host "$logEntry" -Foregroundcolor Red
    }
    elseif ($warning) {
        Write-Warning "$logEntry" ; $logEntry = "[WARNING] $logEntry"
    }
    elseif ($progress) {
        Write-Host "$logEntry" -Foregroundcolor Green
    }
    elseif ($display) {
        Write-Host "$logEntry" 
    }
  
    $logEntry = ((Get-Date -uformat "%D %T") + " - " + $logEntry)
    $logEntry | Out-File $logFile -Append
}


# Start of the Script functions

"============ START : ScriptRun of SpilloverVirtualDesktopMachineCatalog.ps1 at $outputdate ======================= "  | LogMe -display -progress


CheckFreeVDIsMC1


"============ END : ScriptRun of SpilloverVirtualDesktopMachineCatalog.ps1 at $outputdate ======================= "  | LogMe -display -progress
" "  | LogMe -display -progress
" "  | LogMe -display -progress



