<#   
.SYNOPSIS   
Script to automate configuration of a file server (FS)
    
.DESCRIPTION 
This script will configure computer name, join domain, partition disk, create shares and mirror them
Supports save points

.DESCRIPTION - LIST OF RESTORE POINTS											ADD custom manual load point
010 - Computer name and Domain													MISSING
040 - Partitioning disk
050 - Creating shares > Exporting shares
060 - Creating shares > Creating shares
070 - Mirroring shares															ADD per share restore + Optimize double syncs (child items synced by parent)
999 - End of script
	
.PARAMETER
	-OldFs																		ADD in registry to load info
		This is the old FS from which shares will be copied over to the new FS

.NOTES   
Name:        FileServerSetup.ps1
Author:      Samuel Giroux
DateUpdated: 2020-12-18
Version:     0.2.6

#>

Param (
	[Parameter(Mandatory=$true)]
	[String[]]
	$OldFs
)

$LausercoReg="HKLM:\Software\Lauserco\FileServerSetup.ps1"

# Initializing
Clear-Host
Write-Host "Initializing..."
If (!$(Test-Path -Path $LausercoReg)) {
	Write-Host "First run, starting up"
	New-Item -Path $LausercoReg -Force
	New-ItemProperty -Path $LausercoReg -Name State -PropertyType DWord -Value 0
} Else {
	Do {
		$Iteration = 0
		If ($(Get-ItemProperty -Path $LausercoReg -Name "State").State -eq 999) {
			$Answer = Read-Host -Prompt "Script process successful, really run again? (Yes/No)"
		} Else {
			$Answer = Read-Host -Prompt "Save found, restoring? (Yes/No)"
		}
		If ($Answer -Like "y*") {
			If ($Load -lt 999) {
				Write-Host "Loading...`n"
				$Load = $(Get-ItemProperty -Path $LausercoReg -Name "State").State
			} Else {
				Write-Host "Starting over"
				$Load = 0
			}
		} ElseIf ($Answer -Like "n*") {
			Write-Host "Starting over"
			$Load = 0
		} Else {
			If ($Iteration -gt 2) {
				Clear-Host
				Write-Host "Closing, goodbye"
				Read-Host -Prompt "Press Enter to exit" 1> $null
				exit
			} Else {
				Write-Host "Sorry, I did not get that"
				$Iteration++
			}
		}
	} Until ($Answer -Like "y*" -Or $Answer -Like "n*")
}

# 040 - Partitioning disk
If ($Load -le 40) {
	# Partitioning Disk
	$Error.clear()
	Get-Volume -DriveLetter D 2>&1 1> $null
	If ($Error) {
		Write-Host "Creating partition for DATA"
		$Error.clear()
		New-Partition -DiskNumber 0 -UseMaximumSize -DriveLetter D 1> $null
		If ($Error) {
			Write-Host "Cannot create partition, check manually"
			Read-Host -Prompt "Press Enter to continue" 1> $null
		} Else {
			Format-Volume -DriveLetter D -FileSystem NTFS
		}
	} Else {
		Read-Host -Prompt "Partition already exists, press Enter to continue" 1> $null
	}
	Set-ItemProperty -Path $LausercoReg -Name "State" -Value 41
}

# 050 - Creating shares > Exporting shares
If ($Load -le 50) {
	## Creating shares
	# Exporting shares
	Write-Host "Connecting to $OldFs"
	$Error.clear()
	New-CimSession -ComputerName $OldFs 1> $null
	If ($Error) {
		Write-Host "Unable to connect to specified FS"
		Write-Host "Closing"
		Read-Host -Prompt "Press Enter to exit" 1> $null
		exit
	} Else {
		Write-Host "Connection established`n"
	}
	Get-SmbShare -CimSession $OldFs | Select Name, Path, NewPath | Export-Csv -Encoding UTF8 -Path $Env:Userprofile\Desktop\Smb.csv
	Write-Host "Edit the Smb.csv file on the Desktop"
	Write-Host "Keep only the shares to migrate"
	Write-Host "Complete the column NewPath which is the path of the share on the new FS"
	Write-Host "Note: Remove all printers from the list"
	Set-ItemProperty -Path $LausercoReg -Name "State" -Value 51
	# Waiting for user to fix CSV file
	Read-Host -Prompt "Press Enter to continue" 1> $null
}
# 060 - Creating shares > Creating shares
If ($Load -le 60) {
	# Testing OldFs connection
	Write-Host "Making sure" $OldFs "is still reachable..."
	Get-CimSession -ComputerName $OldFs 2>&1 1> $null
	If ($Error) {
		Write-Host "Reconnecting..."
		$Error.clear()
		New-CimSession -ComputerName $OldFs 2>&1 1> $null
		If ($Error) {
			Write-Host "Cannot connect to" $OldFs ", closing"
			Read-Host -Prompt "Press Enter to exit" 1> $null
			exit
		} Else {
			Write-Host "Connection established, continuing"
		}
	} Else {
		Write-Host "Is alive, continuing"
	}
	# Creating shares
	Write-Host "Processing tree"
	Import-Csv -Path $Env:Userprofile\Desktop\Smb.csv | ForEach-Object {
		Write-Host "Selected leaf" $_.Name
		If (!$(Test-Path -Path $_.NewPath)) {
			New-Item -Path $_.NewPath -ItemType Directory 1> $null
			Write-Host "Created folder"
		}
		$Error.clear()
		$LocalShares = Get-SmbShare | Select Name
		If (!($LocalShares -Match $_.Name)) {
			New-SmbShare -Name $_.Name -Path $_.NewPath 1> $null
			Get-SmbShareAccess -CimSession $OldFs -Name $_.Name | ForEach-Object {
				Grant-SmbShareAccess -Name $_.Name -AccountName $_.AccountName -AccessRight $_.AccessRight -Force 1> $null
			}
			If ($Error) {
				Read-Host -Prompt "Something happened. Check error, then press Enter to continue." 1> $null
			} Else {
				Write-Host "Created share`n"
			}
		} Else {
			Write-Host "Share" $_.Name "already exists, skipping"
		}
	}
	# Closing connections
	Get-CimSession | Remove-CimSession
	Set-ItemProperty -Path $LausercoReg -Name "State" -Value 61
}

# 070 - Mirroring shares
If ($Load -le 70) {
	# Mirroring shares
	Do {
		$Iteration = 0
		$Answer = Read-Host -Prompt "Ready to clone shares? (Yes/No)"
		If ($Answer -Like "y*") {} ElseIf ($Answer -Like "n*") {
			Clear-Host
			Write-Host "Closing script"
			Write-Host "You can run this script again to get back to this point"
			Read-Host -Prompt "Press Enter to exit" 1> $null
			exit
		} Else {
			If ($Iteration -gt 2) {
				Clear-Host
				Write-Host "Closing, goodbye"
				Read-Host -Prompt "Press Enter to exit" 1> $null
				exit
			} Else {
				Write-Host "Sorry, I did not get that"
				$Iteration++
			}
		}
	} Until ($Answer -Like "y*" -Or $Answer -Like "n*")
	Import-Csv -Path $Env:Userprofile\Desktop\Smb.csv | ForEach-Object {
		$Error.clear()
		Write-Host "Starting mirror of" $_.Name
		$NetworkPath = ("\\$OldFs\" + $_.Path -Replace ":","$")
		robocopy $NetworkPath $_.NewPath /MIR /SEC /E /NDL /R:3 /W:3 /LOG:C:\robolog_$($_.Name).txt
		If ($Error) {
			Read-Host -Prompt "Something happened. Check error, then press Enter to continue." 1> $null
		} Else {
			Write-Host "Mirrored share    " $_.Name
		}
	}
	Set-ItemProperty -Path $LausercoReg -Name "State" -Value 71
}

# 999 - End of script
Do {
	$Iteration = 0
	Write-Host "End of configuration. Mark as completed? (Yes/No)"
	$Answer = Read-Host -Prompt "Answering No will enable to load back to last step"
	If ($Answer -Like "y*") {
		Set-ItemProperty -Path $LausercoReg -Name "State" -Value 999
	} ElseIf ($Answer -Like "n*") {
		Write-Host "Keeping last save point"
	} Else {
		If ($Iteration -gt 2) {
			Write-Host "Closing, goodbye"
			Read-Host -Prompt "Press Enter to exit" 1> $null
			exit
		} Else {
			Write-Host "Sorry, I did not get that"
			$Iteration++
		}
	}
} Until ($Answer -Like "y*" -Or $Answer -Like "n*")
Write-Host "End of script"
Write-Host "Have a nice day!"
Start-Sleep 8
exit
