#=======================================================#
# Import modules for Active Directory to scan computers #
# and SSH-Sessions for connecting to switches.          #
#=======================================================#
Import-Module ActiveDirectory
Import-Module ".\Modules\SSH-Sessions"
Add-Type -Path ".\Modules\Renci.SshNet35.dll"

#=====================================================#
# Try to load the settingsfile from the user's system #
# If it fails the variables will be blank by default. #
# If it succeeds they will be given the values that   #
# were loaded from the settings file.                 #
#=====================================================#
Try {
    $loadedParams = Get-Content .\dFiles\settings -ErrorAction SilentlyContinue
    $script:domain = $loadedParams[0]
    $script:computerOU = $loadedParams[1]
}
Catch {
    $script:domain   = ""
    $script:computerOU = ""
}

# Create a variable for the scanned systems
# This is the data source for the DataGridView
$script:inventory = New-Object System.Collections.ArrayList
#$script:switches = New-Object System.Collections.ArrayList

#=============================================#
# Load the .NET assemblies for creating a GUI #
#=============================================#
[reflection.assembly]::loadWithPartialName("System.Windows.Forms") | Out-Null
[reflection.assembly]::loadWithPartialName("System.Drawing") | Out-Null
[System.Windows.Forms.Application]::EnableVisualStyles()

function giveMeNewWindow() {
       #Display a new window to ask the user what they want to do with these accounts
       $outWindow = New-Object System.Windows.Forms.Form
	   $outWindowSize = New-Object System.Drawing.Size
	   $outWindowSize.Width = 508
	   $outWindowSize.Height = 690
	   $outWindow.ClientSize = $outWindowSize
       $outWindow.FormBorderStyle = "Fixed3D"
       $outWindow.MaximizeBox = $False
       $outWindow.StartPosition = "CenterScreen"
       return $outWindow
}

function giveMeNewButton() {
	$newButton = New-Object System.Windows.Forms.Button
	$newButton.Size = New-Object System.Drawing.Size(120, 50)
	$newButton.Font = New-Object System.Drawing.Font("Helvetica", "11")
	return $newButton
}

$mainWindow = giveMeNewWindow
$mainWindow.Text = "SysTrack"
$mainWindow.StartPosition = "CenterScreen"

#Create a DataGridView for displaying the computers as they are scanned
$computerGridView = New-Object System.Windows.Forms.DataGridView
$computerGridView.ReadOnly = $True
$computerGridView.Size = New-Object System.Drawing.Size 508, 590
$computerGridView.AutoSizeColumnsMode = 16
$computerGridView.DataBindings.DefaultDataSourceUpdateMode = 0

$startButton = giveMeNewButton
$startButton.Location = New-Object System.Drawing.Point(15, 600)
$startButton.Text = "Start Inventory"
$startButton.Add_Click({
	$startButton.Enabled = $false
	$importButton.Enabled = $false
	$exportButton.Enabled = $false
	$locateButton.Enabled = $false
	$settingsButton.Enabled = $false
	$clearConsoleButton.Enabled = $false
	takeInventory
})

$importButton = giveMeNewButton
$importButton.Location = New-Object System.Drawing.Point(135, 600)
$importButton.Text = "Import Inventory"
$importButton.Add_Click({
	importInventory
})

$exportButton = giveMeNewButton
$exportButton.Location = New-Object System.Drawing.Point(255, 600)
$exportButton.Text = "Export Inventory"
$exportButton.Add_Click({
	exportInventory
})

$locateButton = giveMeNewButton
$locateButton.Location = New-Object System.Drawing.Point(375, 600)
$locateButton.Text = "Locate System"
$locateButton.Add_Click({
	Write-Host "`n"
	$computerToLocate = $computerGridView.CurrentCell.Value
	$ping = New-Object System.Net.NetworkInformation.Ping
	$ret = $ping.Send("$computerToLocate")
	if ($ret.Status -eq "Success") {
		$IPAddress = $ret.Address.ToString()
	} else {
		throw "[-] Pinging the system failed [-]"
		return
	}
	
	#First add the Layer 3 switches to search for the MAC by IP
	$switch = Get-Content ".\dFiles\Layer3Switches.txt"
	$found = 0
	
	# Begin tracing the system through the switches
	swiTrace "sho ip arp | i $IPAddress | ex" $switch "" | ForEach {
		if ($_) {
			$found = 1
			$regex = '[A-Fa-f0-9]{4}\.[A-Fa-f0-9]{4}\.[A-Fa-f0-9]{4}'
			$_ -match $regex
			$MAC = $matches[0]
			
			#Trace the machine on the layer 2 switches to find its location
			$switch = Get-Content ".\dFiles\Layer2Switches.txt"
			$index = 0
			$switch_port = New-Object System.Collections.ArrayList
			swiTrace "sho mac add | i $MAC" $switch "-Quiet" | ForEach {
				if ($_) {
					$regex = '[GiFa]{2}[0-4]/[0-9]{1,2}(/[0-9]{0,2}){0,1}'
					$_ -match $regex
					$interface = $matches[0]
					$table = @{}
					$table.Add("Switch", $switch[$index]) | Out-NULL
					$table.Add("Interface", $interface) | Out-NULL
					$switch_port.Add($table) | Out-NULL
				}
				$index++
			}
			foreach ($switch_ht in $switch_port) {
				$single_switch = $switch_ht.Get_Item("Switch")
				$interface = $switch_ht.Get_Item("Interface")
				swiTrace "sho run int $interface | i switchport mode access" $single_switch "-Quiet" | ForEach {
					if ($_ -eq " switchport mode access") {
						Write-Host "`n[!] System was found on switch $single_switch port $interface [!]" -foregroundcolor cyan
						[System.Windows.Forms.MessageBox]::Show("$computerToLocate was found on $single_switch port $interface.", "System Found")
						break
					}
				}
			}
		}
	}
	if ($found -eq 0) {
		Write-Host "`n[!] $computerToLocate could not be found on the Layer 3 switches specified [!]" -foregroundcolor red
		[System.Windows.Forms.MessageBox]::Show("$computerToLocate could not be found on the Layer 3 switches specified.", "System Could Not Be Found")
	}
})

$clearConsoleButton = giveMeNewButton
$clearConsoleButton.Location = New-Object System.Drawing.Point 255, 655
$clearConsoleButton.Size = New-Object System.Drawing.Size(180, 30)
$clearConsoleButton.Font = New-Object System.Drawing.Font("Helvetica", "9")
$clearConsoleButton.Text = "Clear Console"
$clearConsoleButton.Add_Click({clear})

$settingsButton = giveMeNewButton
$settingsButton.Location = New-Object System.Drawing.Point(85, 655)
$settingsButton.Size = New-Object System.Drawing.Size(170, 30)
$settingsButton.Font = New-Object System.Drawing.Font("Helvetica", "9")
$settingsButton.Text = "Settings"
$settingsButton.Add_Click({
	$settingsWindow = giveMeNewWindow
	$settingsWindow.Size = New-Object System.Drawing.Size 500, 250
    $settingsWindow.Text = "SysTrack Settings"
	
	#These are info labels for the user
    $labelPoint = New-Object System.Drawing.Point 10, 30

    #Domain Label
    $domainLabel = New-Object System.Windows.Forms.Label
    $domainLabel.Text = "                      Domain:"

    #Computer OU Label
    $computerOULabel = New-Object System.Windows.Forms.Label
    $computerOULabel.Text = "             Computer OU:"

    $labels = @($domainLabel, $computerOULabel)
    foreach ($label in $labels) {
        $label.Width = 145
        $label.Height = 20
        $label.Font = New-Object System.Drawing.Font("Helvetica", "10")
        $label.Location = $labelPoint
        $labelPoint.Y += 26
    }
    
    #Create text fields for the properties
    $domainField = New-Object System.Windows.Forms.TextBox
    $domainField.Text = dottedString($domain)
    $domainField.Location = New-Object System.Drawing.Point 155, 30
    $domainField.Size = New-Object System.Drawing.Size 200, 20
    
    $computerField = New-Object System.Windows.Forms.TextBox
    $computerField.Text = dottedString($computerOU)
    $computerField.Location = New-Object System.Drawing.Point 155, 55
    $computerField.Size = New-Object System.Drawing.Size 200, 20
	
	$modifyLayer3Button = giveMeNewButton
	$modifyLayer3Button.Location = New-Object System.Drawing.Point 155, 90
	$modifyLayer3Button.Size = New-Object System.Drawing.Size 200, 30
	$modifyLayer3Button.Text = "Modify Layer 3 Switch List"
	$modifyLayer3Button.Font = New-Object System.Drawing.Font("Helvetica", "10")
	$modifyLayer3Button.Add_Click({
		Invoke-Item ".\dFiles\Layer3Switches.txt"
	})
	
	$modifyLayer2Button = giveMeNewButton
	$modifyLayer2Button.Location = New-Object System.Drawing.Point 155, 120
	$modifyLayer2Button.Size = New-Object System.Drawing.Size 200, 30
	$modifyLayer2Button.Text = "Modify Layer 2 Switch List"
	$modifyLayer2Button.Font = New-Object System.Drawing.Font("Helvetica", "10")
	$modifyLayer2Button.Add_Click({
		Invoke-Item ".\dFiles\Layer2Switches.txt"
	})
    
    #Create a button to save the data
    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Size = New-Object System.Drawing.Size 100, 30
    $saveButton.Location = New-Object System.Drawing.Point 200, 170
    $saveButton.Text = "Save Settings"
    $saveButton.add_Click({saveSettings(@($domainField.Text,$computerField.Text))})
	
	$fieldControls = @($domainField, $computerField, $modifyLayer3Button, $modifyLayer2Button, $saveButton)
    
    #Add the labels to the console window
	$labels | ForEach {
		$settingsWindow.Controls.Add($_)
	}
	$fieldControls | ForEach {
		$settingsWindow.controls.Add($_)
	}
	$settingsWindow.ShowDialog()
})

function swiTrace([String]$command, $switches, [String]$quiet) {
	#=====================================================================================#
	# Try to load the user's credentials.  If there is no file saved then prompt the user #
	# for their username and password.  These credentials should be for the remote system #
	# and not the user's local login.                                                     #
	#=====================================================================================#
	Try {
		$creds = Get-Content ".\dFiles\credentials" -ErrorAction SilentlyContinue
		$username = $creds[0]
		$password = $creds[1] | ConvertTo-SecureString
	}
	Catch {
		$creds = Get-Credential
		$username = $creds.Username -replace "\\", ""
		$password = $creds.Password
		$creds = $username,($password | ConvertFrom-SecureString)
		$creds | out-file ".\dFiles\credentials"
	}

	#==========================================================#
	# Convert the password to plain text to send to the server #
	#==========================================================#
	$password = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))

	# Create an array ($res) to hold the results for each of the commands
	# and load the commands to send to the server(s) into the $commands var.
	# Begin iterating through the commands, sending them one by one to each
	# server for processing.  The results will be stored in $res.
	$res = New-Object System.Collections.ArrayList
	
	#Create a new SSH connection
	New-SshSession -ComputerName $switches -Username $username -Password $password | Out-NULL
	
	#Invoke a command on the switch
	$str = $switches | Out-String
	Write-Host "Sending Command: " -nonewline
	Write-Host "$command" -foregroundcolor Blue -nonewline
	Write-Host " to $str"
	if ($quiet -eq "-Quiet") {
		$temp = Invoke-SshCommand -Computer $switches -Command "$command" -Quiet
	} else {
		$temp = Invoke-SshCommand -Computer $switches -Command "$command"
	}
	if($temp.GetType().FullName -eq "System.Object[]") {
		$temp.SyncRoot | ForEach {
			$res.Add($_) | Out-NULL
		}
	} else {
		$res.Add($temp) | Out-NULL
	}
	
	$res
	
	#Remove connection
	Try {
		Remove-SshSession -RemoveAll -Quiet | Out-NULL
	} Catch {}
}

function takeInventory() {
	#Get all the computers from the search base
	$computers = Get-ADComputer -Fil * -SearchBase "$computerOU, $domain" | foreach {$_.Name} | sort
	
	foreach ($computer in $computers) {
		Try {
			$output = New-Object System.Collections.Specialized.OrderedDictionary
			$name = Get-WMIObject Win32_ComputerSystemProduct -ComputerName $computer -ErrorAction SilentlyContinue | foreach {$_.IdentifyingNumber}
			$serial = Get-WMIObject Win32_PhysicalMedia -ComputerName $computer -ErrorAction SilentlyContinue | foreach {$_.SerialNumber}
			$serial = $serial[0]
			$output.Add("Computer Serial", $name)
			$output.Add("HDD Serial", ($serial -replace " ", ""))
			$output.Add("Computer Name", $computer)
			$inventory.Add($(New-Object PSObject -Property $output)) | Out-NULL

			$x++
		}
		Catch {
			continue
		}
		Finally {
			#Update the progress bar
			Write-Progress -Activity "Scanning Network" -Status "Current System: $computer" -percentComplete ($x / $computers.count * 100)
		}
	}
	#Update the computerGridView to display the systems
	$computerGridView.DataSource = $inventory
	$computerGridView.EndEdit()
	$computerGridView.Refresh()
	$mainWindow.Refresh()
	Write-Progress -Activity "Scanning Network" -Status "Complete" -Complete
	
	#Once the inventory is complete re-enable the buttons
	$startButton.Enabled = $true
	$importButton.Enabled = $true
	$exportButton.Enabled = $true
	$locateButton.Enabled = $true
	$settingsButton.Enabled = $true
	$clearConsoleButton.Enabled = $true
}

function importInventory() {
	$open = New-Object System.Windows.Forms.OpenFileDialog
	$open.Filter = "CSV (*.csv) | *.csv*"
	$open.Title = "Import Inventory"
	$open.SupportMultiDottedExtensions = $True
	$open.ShowHelp = $true
	if ($open.ShowDialog() -eq "OK") {
		$inventory.AddRange($(Import-CSV $open.FileName))
		
		#Update the computerGridView to display the systems
		$computerGridView.DataSource = $inventory
		$computerGridView.Update()
		$computerGridView.Refresh()
		$mainWindow.Refresh()
	}
}

function exportInventory() {
    $save = New-Object System.Windows.Forms.SaveFileDialog
    $save.CreatePrompt = $False
    $save.SupportMultiDottedExtensions = $True
    $save.DefaultExt = "csv"
    $save.ShowHelp = $true
    $save.Filter = "CSV (*.csv) | *.csv*"
    $save.Title = "Export Inventory"
    if ($save.ShowDialog() -eq "OK") {
        $inventory | export-csv $save.FileName -NoTypeInformation
    }
}

function saveSettings([Array]$params) {
    #Convert parameters back to original state
    $params[0] = convertToDC($params[0])
    $script:domain = $params[0]
    
    $params[1] = convertToOU($params[1])
    $script:computerOU = $params[1]
    
    $params | out-file .\dFiles\settings
    [System.Windows.Forms.MessageBox]::Show("Settings successfully saved!", "Inventory Settings")
}

function convertToDC([String]$str) {
    $dcStr = New-Object System.Collections.ArrayList
    foreach ($item in $str.split(".")) {
        $dcStr += "DC=$item"
    }
    return [System.String]::Join(", ", $dcStr)
}

function convertToOU([String]$str) {
    $dcStr = New-Object System.Collections.ArrayList
    foreach ($item in $str.split(".")) {
        $dcStr += "OU=$item"
    }
    return [System.String]::Join(", ", $dcStr)
}

function dottedString([String] $str) {
    $temp = $str -replace "DC=", ""
    $temp = $temp -replace "OU=", ""
    return $temp -replace ", ", "."
}
$controls = @($computerGridView, $startButton, $importButton, $exportButton, $locateButton, $settingsButton, $clearConsoleButton)
$controls | ForEach {
	$mainWindow.Controls.Add($_)
}
$mainWindow.ShowDialog() | Out-NULL