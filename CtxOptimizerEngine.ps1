<#
.SYNOPSIS
    Citrix Optimization Engine helps to optimize operating system to run better with XenApp or XenDesktop solutions.

.DESCRIPTION
    Citrix Optimization Engine helps to optimize operating system to run better with XenApp or XenDesktop solutions. This script can run in three different modes - Analyze, Execute and Rollback. Each execution will automatically generate an XML file with a list of performed actions (stored under .\Logs folder) that can be used to rollback the changes applied. 

.PARAMETER Source
    Source XML file that contains the required configuration. Typically located under .\Templates folder. This file provides instructions that CTXOE can process. Template can be specified with or without .xml extension and can be full path or just a filename. If you specify only filename, template must be located in .\Templates folder.
    If -Source or -Template is not specified, Optimizer will automatically try to detect the best suitable template. It will look in .\Templates folder for file called <templateprefix>_<OS>_<build>. See help for -templateprefix to learn more about using your own custom templates.

.PARAMETER TemplatePrefix
    When -Source or -Template parameter is not specified, Optimizer will try to find the best matching template automatically. By default, it is looking for templates that start with "Citrix_Windows" and are provided by Citrix as part of default Optimizer build. If you would like to use your own templates with auto-select, you can override the default templates prefix. 
    For example if your template is called My_Windows_10_1809.xml, use '-TemplatePrefix "My_Windows"' to automatically select your templates based on current operating system and build.

.PARAMETER Mode
    CTXOE supports three different modes:
        Analyze - Do not apply any changes, only show the recommended changes.
        Execute - Apply the changes to the operating system.
        Rollback - Revert the applied changes. Requires a valid XML backup from the previously run Execute phase. This file is usually called Execute_History.xml.

    WARNING: Rollback mode cannot restore applications that have been removed. If you are planning to remove UWP applications and want to be able to recover them, use snapshots instead of rollback mode.

.PARAMETER IgnoreConditions
    When you use -IgnoreConditions switch, all conditions are skipped and optimizations are applied without any environments tests. This is used mostly for troubleshooting and is not recommended for normal environments.

.PARAMETER Groups
    Array that allows you to specify which groups to process from a specified source file.

.PARAMETER OutputLogFolder
    The location where to save all generated log files. This will replace an automatically generated folder .\Logs and is typically used with ESD solutions like SCCM.

.PARAMETER OutputXml
    The location where the output XML should be saved. The XML with results is automatically saved under .\Logs folder, but you can optionally specify also other location. This argument can be used together with -OutputHtml.

.PARAMETER OutputHtml
    The location where the output HTML report should be saved. The HTML with results is automatically saved under .\Logs folder, but you can optionally specify another location. This argument can be used together with -OutputXml.

.PARAMETER OptimizerUI
    Parameter used by Citrix Optimizer Tool UI to retrieve information from optimization engine. For internal use only.

.EXAMPLE
    .\CtxOptimizerEngine.ps1 -Source C:\Temp\Win10.xml -Mode Analyze
    Process all entries in Win10.xml file and display the recommended changes. Changes are not applied to the system.

.EXAMPLE
    .\CtxOptimizerEngine.ps1 -Source C:\Temp\Win10.xml -Mode Execute
    Process all entries from Win10.xml file. These changes are applied to the operating system.

.EXAMPLE
    .\CtxOptimizerEngine.ps1 -Source C:\Temp\Win10.xml -Mode Execute -Groups "DisableServices", "RemoveApplications"
    Process entries from groups "Disable Services" and "Remove built-in applications" in Win10.xml file. These changes are applied to the operating system.

.EXAMPLE
    .\CtxOptimizerEngine.ps1 -Source C:\Temp\Win10.xml -Mode Execute -OutputXml C:\Temp\Rollback.xml
    Process all entries from Win10.xml file. These changes are applied to the operating system. Save the rollback instructions in the file rollback.xml.

.EXAMPLE
    .\CtxOptimizerEngine.ps1 -Source C:\Temp\Rollback.xml -Mode Rollback
    Revert all changes from the file rollback.xml.

.NOTES
    Author: Martin Zugec
    Date:   February 17, 2017

.LINK
    https://support.citrix.com/article/CTX224676
#>

#Requires -Version 2

Param (
    [Alias("Template")]
    [System.String]$Source,

    [ValidateSet('analyze','execute','rollback')]

    [System.String]$Mode = "Analyze",

    [Array]$Groups,

    [String]$OutputLogFolder,

    [String]$OutputHtml,

    [String]$OutputXml,

    [Switch]$OptimizerUI,

    [Switch]$IgnoreConditions,

    [String]$TemplatePrefix
)

[String]$OptimizerVersion = "2.7";
# Retrieve friendly OS name (e.g. Winodws 10 Pro)
[String]$m_OSName = $(Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name ProductName).ProductName;
# If available, retrieve a build number (yymm like 1808). This is used on Windows Server 2016 and Windows 10, but is not used on older operating systems and is optional
[String]$m_OSBuild = $(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name ReleaseID -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ReleaseID);

Write-Host "------------------------------"
Write-Host "| Citrix Optimization Engine |"
Write-Host "| Version $OptimizerVersion                |"
Write-Host "------------------------------"
Write-Host

Write-Host "Running in " -NoNewline
Write-Host -ForegroundColor Yellow $Mode -NoNewLine
Write-Host " mode"

# Error handling. We want Citrix Optimizer Tool to abort on any error, so error action preference is set to "Stop".
# The problem with this approach is that if Optimizer is called from another script, "Stop" instruction will apply to that script as well, so failure in Optimizer engine will abort calling script(s).
# As a workaround, instead of terminating the script, Optimizer has a global error handling procedure that will restore previous setting of ErrorActionPreference and properly abort the execution.
$OriginalErrorActionPreferenceValue = $ErrorActionPreference;
$ErrorActionPreference = "Stop";

Trap {
    Write-Host "Citrix Optimizer Tool engine has encountered a problem and will now terminate";
    $ErrorActionPreference = $OriginalErrorActionPreferenceValue;
    Write-Error $_;

    # Update $Run_Status with error encountered and save output XML file.
    If ($Run_Status) {
        $Run_Status.run_successful = $False.ToString();
        $Run_Status.run_details = "Error: $_";
        $Run_Status.time_end = [DateTime]::Now.ToString('yyyy-MM-dd_HH-mm-ss') # Saving DateTime in predefined format. This is required, since we don't know the target localization settings and want to make sure that UI and engine can communicate in same language.
        $PackDefinitionXml.Save($ResultsXml);
    }

    Return $False;
}

# Create enumeration for PluginMode. Enumeration cannot be used in the param() section, as that would require a DynamicParam on a script level.
[String]$PluginMode = $Mode;

# Just in case if previous run failed, make sure that all modules are reloaded
Remove-Module CTXOE*;

# Create $CTXOE_Main variable that defines folder where the script is located. If code is executed manually (copy & paste to PowerShell window), current directory is being used
If ($MyInvocation.MyCommand.Path -is [Object]) {
    [string]$Global:CTXOE_Main = $(Split-Path -Parent $MyInvocation.MyCommand.Path);
} Else {
    [string]$Global:CTXOE_Main = $(Get-Location).Path;
}

# Create Logs folder if it doesn't exists
If ($OutputLogFolder.Length -eq 0) {
    $Global:CTXOE_LogFolder = "$CTXOE_Main\Logs\$([DateTime]::Now.ToString('yyyy-MM-dd_HH-mm-ss'))"
} Else {
    $Global:CTXOE_LogFolder = $OutputLogFolder;
}

If ($(Test-Path "$CTXOE_LogFolder") -eq $false) {
    Write-Host "Creating Logs folder $(Split-Path -Leaf $CTXOE_LogFolder)"
    MkDir $CTXOE_LogFolder | Out-Null
}

# Report the location of log folder to UI
If ($OptimizerUI) {
    $LogFolder = New-Object -TypeName PSObject
    $LogFolder.PSObject.TypeNames.Insert(0,"logfolder")
    $LogFolder | Add-Member -MemberType NoteProperty -Name Location -Value $CTXOE_LogFolder
    Write-Output $LogFolder
}

# Initialize debug log (transcript). PowerShell ISE doesn't support transcriptions at the moment.
# Previously, we tried to determine if current host supports transcription or not, however this functionality is broken since PowerShell 4.0. Using Try/Catch instead.
Write-Host "Starting session log"
Try {
    $CTXOE_DebugLog = "$CTXOE_LogFolder\Log_Debug_CTXOE.log"
    Start-Transcript -Append -Path "$CTXOE_DebugLog" | Out-Null
} Catch { Write-Host "An exception happened when starting transcription: $_" -ForegroundColor Red }

# Check if user is administrator
Write-Host "Checking permissions"
If (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Throw "You must be administrator in order to execute this script"
}

# Check if template name has been provided. If not, try to detect proper template automatically
If ($Source.Length -eq 0 -or $Source -eq "AutoSelect") {
    Write-Host "Template not specified, turning on auto-select mode";
    
    # Multiple template prefixes can be used - users can have their own custom templates.
    [array]$m_TemplatePrefixes = @();
    If ($TemplatePrefix.Length -gt 0) {
        Write-Host "Custom template prefix detected: $TemplatePrefix";
        $m_TemplatePrefixes += $TemplatePrefix;
    }
    $m_TemplatePrefixes += "Citrix_Windows";
    
    # Strip the description, keep only numbers. Special processing is required to include "R2" versions. Result of this regex is friendly version number (7, 10 or '2008 R2' for example)
    [String]$m_TemplateNameOSVersion = $([regex]"([0-9])+\sR([0-9])+|[(0-9)]+").Match($m_OSName).Captures[0].Value.Replace(" ", "");
    
    # Go through all available template prefixes, starting with custom prefix. Default Citrix prefix is used as a last option
    ForEach ($m_TemplateNamePrefix in $m_TemplatePrefixes) {

        Write-Host "Trying to find matching templates for prefix $m_TemplateNamePrefix"

        # If this is server OS, include "Server" in the template name. If this is client, don't do anything. While we could include _Client in the template name, it just looks weird.
        If ((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name InstallationType).InstallationType -eq "Server") {
            $m_TemplateNamePrefix += "_Server";
            If ($TemplatePrefix.Length -gt 0) {$m_TemplateNameCustomPrefix += "_Server";}
        }

        # First, we try to find if template for current OS and build is available. If not, we tried to find last build for the same OS version. If that is not available, we finally check for generic version of template (not build specific)
        If (Test-Path -Path "$CTXOE_Main\Templates\$(($m_TemplateNamePrefix) + '_' + ($m_TemplateNameOSVersion) + '_' + ($m_OSBuild)).xml") {
            Write-Host "Template detected - using optimal template for current version and build";
            $Source = "$CTXOE_Main\Templates\$(($m_TemplateNamePrefix) + '_' + ($m_TemplateNameOSVersion) + '_' + ($m_OSBuild)).xml";
            Break;
        } Else {
            Write-Host "Preferred template $(($m_TemplateNamePrefix) + '_' + ($m_TemplateNameOSVersion) + '_' + ($m_OSBuild)) was not found, using fallback mode"
            [array]$m_PreviousBuilds = Get-ChildItem -Path "$CTXOE_Main\Templates" -Filter $($m_TemplateNamePrefix + '_' + ($m_TemplateNameOSVersion) + '_*');
            # Older versions of PowerShell (V2) will automatically delect object instead of initiating an empty array.
            If ($m_PreviousBuilds -isnot [Object] -or $m_PreviousBuilds.Count -eq 0) {
                If (Test-Path -Path "$CTXOE_Main\Templates\$(($m_TemplateNamePrefix) + '_' + ($m_TemplateNameOSVersion)).xml") {
                    Write-Host "Template detected - using generic template for OS version";
                    $Source = "$CTXOE_Main\Templates\$(($m_TemplateNamePrefix) + '_' + ($m_TemplateNameOSVersion)).xml";
                    Break;
                }
            } Else {
                Write-Host "Template detected - using previous OS build";
                $Source = "$CTXOE_Main\Templates\$($m_PreviousBuilds | Sort-Object Name | Select-Object -ExpandProperty Name -Last 1)";
                Break;
            }
        }
    
    }

    If ($Source.Length -eq 0 -or $Source -eq "AutoSelect")  {Throw "Auto-detection of template failed, no suitable template has been found"}

}

# Check if -Source is a fullpath or just name of the template. If it's just the name, expand to a fullpath.
If (-not $Source.Contains("\")) {
    If (-not $Source.ToLower().EndsWith(".xml")) {
         $Source = "$Source.xml";
    }

    $Source = "$CTXOE_Main\Templates\$Source";
}

# Specify the default location of output XML
[String]$ResultsXml = "$CTXOE_LogFolder\$($PluginMode)_History.xml"
If ($OutputHtml.Length -eq 0) {
    [String]$OutputHtml = "$CTXOE_LogFolder\$($PluginMode)_History.html"
}

Write-Host
Write-Host "Processing definition file $Source"
[Xml]$PackDefinitionXml = Get-Content $Source

# Try to find if this template has been executed before. If <runstatus /> is present, move it to history (<previousruns />). This is used to store all previous executions of this template.
If ($PackDefinitionXml.root.run_status) {
    # Check if <previousruns /> exists. If not, create a new one.
    If (-not $PackDefinitionXml.root.previousruns) {
        $PackDefinitionXml.root.AppendChild($PackDefinitionXml.CreateElement("previousruns")) | Out-Null;
    }

    $PackDefinitionXml.root.Item("previousruns").AppendChild($PackDefinitionXml.root.run_status) | Out-Null;
}

# Create new XML element to store status of the execution.
[System.Xml.XmlElement]$Run_Status = $PackDefinitionXml.root.AppendChild($PackDefinitionXml.ImportNode($([Xml]"<run_status><run_mode /><time_start /><time_end /><entries_total /><entries_success /><entries_failed /><run_successful /><run_details /><optimizerversion /><targetos /><targetcomputer /></run_status>").DocumentElement, $True));
$Run_Status.run_successful = $False.ToString();
$Run_Status.run_mode = $PluginMode;
$Run_Status_Default_Message = "Run started, but never finished";
$Run_Status.run_details = $Run_Status_Default_Message;
$Run_Status.time_start = [DateTime]::Now.ToString('yyyy-MM-dd_HH-mm-ss') # Saving DateTime in predefined format. This is required, since we don't know the target localization settings and want to make sure that UI and engine can communicate in same language.
$Run_Status.optimizerversion = $OptimizerVersion;
$Run_Status.targetcomputer =  $Env:ComputerName;

If ($m_OSBuild.Length -gt 0) {
    $Run_Status.targetos = $m_OSName + " build " + $m_OSBuild;
} Else {
    $Run_Status.targetos = $m_OSName;
}

$PackDefinitionXml.Save($ResultsXml);

# Create new variables for counting of successful/failed/skipped entries execution. This is used in run_status reporting.
$Run_Status.entries_total = $PackDefinitionXml.SelectNodes("//entry").Count.ToString();
[Int]$Run_Status_Success = 0;
[Int]$Run_Status_Failed = 0;

# Add CTXOE modules to PSModulePath variable. With this modules can be loaded dynamically based on the prefix.
Write-Host "Adding CTXOE modules"
$Global:CTXOE_Modules = "$CTXOE_Main\Modules"
$Env:PSModulePath = "$([Environment]::GetEnvironmentVariable("PSModulePath"));$($Global:CTXOE_Modules)"

# Older version of PowerShell cannot load modules on-demand. All modules are pre-loaded.
If ($Host.Version.Major -le 2) {
    Write-Host "Detected older version of PowerShell. Importing all modules manually."
    ForEach ($m_Module in $(Get-ChildItem -Path "$CTXOE_Main\Modules" -Recurse -Filter "*.psm1")) {
        Import-Module -Name $m_Module.FullName
    }
}

# If mode is rollback, check if definition file contains the required history elements
If ($PluginMode -eq "Rollback") {
    If ($PackDefinitionXml.SelectNodes("//rollbackparams").Count -eq 0) {
        Throw "You need to select a log file from execution for rollback. This is usually called execute_history.xml. The file specified doesn't include instructions for rollback"
    }
}

# Display metadata for selected template. This acts as a header information about template
$PackDefinitionXml.root.metadata.ChildNodes | Select-Object Name, InnerText | Format-Table -HideTableHeaders

# First version of templates organized groups in packs. This was never really used and < pack/> element was removed in schema version 2.0
# This code is used for backwards compatibility with older templates
If ($PackDefinitionXml.root.pack -is [System.Xml.XmlElement]) {
    Write-host "Old template format has been detected, you should migrate to newer format" -for Red;
    $GroupElements = $PackDefinitionXml.SelectNodes("/root/pack/group");
} Else {
    $GroupElements = $PackDefinitionXml.SelectNodes("/root/group");
}

# Check if template has any conditions to process. In rollback mode, we do not need to process conditions - they've been already resolved to $True in execute mode and we should be able to rollback all changes.
If ($PluginMode -ne "rollback" -and -not $IgnoreConditions -and $PackDefinitionXml.root.condition -is [Object]) {
    Write-Host
    Write-Host "Template condition detected"
    [Hashtable]$m_TemplateConditionResult = CTXOE\Test-CTXOECondition -Element $PackDefinitionXml.root.condition; 
    Write-Host "Template condition result: $($m_TemplateConditionResult.Result)"
    Write-Host "Template condition details: $($m_TemplateConditionResult.Details)"
    Write-Host
    If ($m_TemplateConditionResult.Result -eq $False) {
        $Run_Status.run_details = "Execution stopped by template condition: $($m_TemplateConditionResult.Details)";
    }
}

# Check if template supports requested mode. If not, abort execution and throw an error
If ($PackDefinitionXml.root.metadata.SelectSingleNode("$($PluginMode.ToLower())_not_supported") -is [System.Xml.XmlElement]) {
    $Run_Status.run_details = "This template does NOT support requested mode $($PluginMode)!";
}


# Process template
ForEach ($m_Group in $GroupElements) {
    Write-Host
    Write-Host "        Group: $($m_Group.DisplayName)"
    Write-Host "        Group ID: $($m_Group.ID)"

    # Proceed only if the current run status message has NOT been modified. This is used to detect scenarios where template is reporting that run should not proceed, e.g. when conditions are used or mode is unsupported.
    If ($Run_Status.run_details -ne $Run_Status_Default_Message) {
        Write-Host "        Template processing failed, skipping"
        Continue
    }

    If ($Groups.Count -gt 0 -and $Groups -notcontains $m_Group.ID) {
        Write-Host "        Group not included in the -Groups argument, skipping"
        Continue
    }

    If ($m_Group.Enabled -eq "0") {
        Write-Host "    This group is disabled, skipping" -ForegroundColor DarkGray
        Continue
    }
    
    # Check if group supports requested mode. If not, move to next group
    [Boolean]$m_GroupModeNotSupported = $m_Group.SelectSingleNode("$($PluginMode.ToLower())_not_supported") -is [System.Xml.XmlElement]

    If ($m_GroupModeNotSupported) {
        Write-Host "    This group does not support $($PluginMode.ToLower()) mode, skipping" -ForegroundColor DarkGray
    }

    # PowerShell does not have concept of loop scope. We need to clear all variables from previous group before we process next group.
    Remove-Variable m_GroupConditionResult -ErrorAction SilentlyContinue;

    # Check if group has any conditions to process. 
    If ($PluginMode -ne "rollback" -and -not $IgnoreConditions -and $m_Group.condition -is [Object]) {
        Write-Host
        Write-Host "        Group condition detected"
        [Hashtable]$m_GroupConditionResult = CTXOE\Test-CTXOECondition -Element $m_Group.condition; 
        Write-Host "        Group condition result: $($m_GroupConditionResult.Result)"
        Write-Host "        Group condition details: $($m_GroupConditionResult.Details)"
        Write-Host
    }

    ForEach ($m_Entry in $m_Group.SelectNodes("./entry")) {
        Write-Host "            $($m_Entry.Name) - " -NoNewline

        If ($m_Entry.Enabled -eq "0") {
            Write-Host "    This entry is disabled, skipping" -ForegroundColor DarkGray
            CTXOE\New-CTXOEHistoryElement -Element $m_Entry -SystemChanged $False -StartTime $([DateTime]::Now) -Result $False -Details "Entry is disabled"
            Continue
        }

        If ($m_Entry.Execute -eq "0") {
            Write-Host " Entry is not marked for execution, skipping" -ForegroundColor DarkGray
            CTXOE\New-CTXOEHistoryElement -Element $m_Entry -SystemChanged $False -StartTime $([DateTime]::Now) -Result $False -Details "Entry is not marked for execution, skipping"
            Continue
        }

        # Check if entry supports requested mode. If not, move to next entry. If parent group does not support this mode, all entries should be skipped.
        # We need to make sure that ALL entries that are skipped have "Execute" set to 0 - otherwise status summary will fail to properly determine if script run was successful or not
        If (($m_GroupModeNotSupported -eq $True) -or ($m_Entry.SelectSingleNode("$($PluginMode.ToLower())_not_supported") -is [System.Xml.XmlElement])) {
            Write-Host "    This entry does not support $($PluginMode.ToLower()) mode, skipping" -ForegroundColor DarkGray
            CTXOE\New-CTXOEHistoryElement -Element $m_Entry -SystemChanged $False -StartTime $([DateTime]::Now) -Result $False -Details "This entry does not support $($PluginMode.ToLower()) mode, skipping"
            $m_Entry.Execute = "0";
            Continue
        }

        # Check if entry supports requested mode. If not, move to next entry
        If ($m_Entry.SelectSingleNode("$($PluginMode.ToLower())_not_supported") -is [System.Xml.XmlElement]) {
            Write-Host "    This entry does not support $($PluginMode.ToLower()) mode, skipping" -ForegroundColor DarkGray
            CTXOE\New-CTXOEHistoryElement -Element $m_Entry -SystemChanged $False -StartTime $([DateTime]::Now) -Result $False -Details "This entry does not support $($PluginMode.ToLower()) mode, skipping"

            Continue
        }

        # Section to process (parent) group conditions and entry conditions. Can be skipped if -IgnoreConditions is used or in rollback mode
        If ($PluginMode -ne "Rollback" -and -not $IgnoreConditions ) {
            # Check if the group condition has failed. If yes, none of the entries should be processed
            If ($m_GroupConditionResult -is [object] -and $m_GroupConditionResult.Result -eq $False) {
                Write-Host "    This entry is disabled by group condition, skipping" -ForegroundColor DarkGray;
                CTXOE\New-CTXOEHistoryElement -Element $m_Entry -SystemChanged $False -StartTime $([DateTime]::Now) -Result $False -Details "FILTERED: $($m_GroupConditionResult.Details)";
                $m_Entry.Execute = "0";
                Continue
            }

            # PowerShell does not have concept of loop scope. We need to clear all variables from previous group before we process next group.
            Remove-Variable m_ItemConditionResult -ErrorAction SilentlyContinue;

            # Check if this item has any conditions to process. 
            If ($m_Entry.condition -is [Object]) {
                Write-Host
                Write-Host "            Entry condition detected"
                [Hashtable]$m_ItemConditionResult = CTXOE\Test-CTXOECondition -Element $m_Entry.condition; 
                Write-Host "            Entry condition result: $($m_ItemConditionResult.Result)"
                Write-Host "            Entry condition details: $($m_ItemConditionResult.Details)"
                Write-Host
                
                If ($m_ItemConditionResult.Result -eq $False) {
                    Write-Host "    This entry is disabled by condition, skipping" -ForegroundColor DarkGray;
                    CTXOE\New-CTXOEHistoryElement -Element $m_Entry -SystemChanged $False -StartTime $([DateTime]::Now) -Result $False -Details "FILTERED: $($m_ItemConditionResult.Details)";
                    $m_Entry.Execute = "0";
                    Continue;
                }
            }
        }

        $m_Action = $m_Entry.SelectSingleNode("./action")
        Write-Verbose "            Plugin: $($m_Action.Plugin)"

        # While some plugins can use only a single set of instructions to perform all the different operations (typically services or registry keys), this might not be always possible.

        # Good example is "PowerShell" plugin - different code can be used to analyze the action and execute the action (compare "Get-CurrentState -eq $True" for analyze to "Set-CurrentState -Mode Example -Setup Mode1" for execute mode).

        # In order to support this scenarios, it is possible to override the default <params /> element with a custom element for analyze and rollback phases. Default is still <params />. With this implementation, there can be an action that will implement all three elements (analyzeparams, rollbackparams and executeparams).

        [String]$m_ParamsElementName = "params"
        [String]$m_OverrideElement = "$($PluginMode.ToLower())$m_ParamsElementName"

        If ($m_Action.$m_OverrideElement -is [Object]) {
            Write-Verbose "Using custom <$($m_OverrideElement) /> element"
            $m_ParamsElementName = $m_OverrideElement
        }

        # To prevent any unexpected damage to the system, Rollback mode requires use of custom params object and cannot use the default one.
        If ($PluginMode -eq "Rollback" -and $m_Action.$m_OverrideElement -isnot [Object]) {
            If ($m_Entry.history.systemchanged -eq "0") {
                Write-Host "This entry has not changed, skip" -ForegroundColor DarkGray
                Continue
            } Else {
                Write-Host "Rollback mode requires custom instructions that are not available, skip" -ForegroundColor DarkGray
                Continue
            }
        }

        # Reset variables that are used to report the status
        [Boolean]$Global:CTXOE_Result = $False;
        $Global:CTXOE_Details = "No data returned by this entry (this is unexpected)";

        # Two variables used by rollback. First identify that this entry has modified the system. The second should contain information required for rollback of those changes (if possible). This is required only for "execute" mode.
        [Boolean]$Global:CTXOE_SystemChanged = $False

        $Global:CTXOE_ChangeRollbackParams = $Null

        [DateTime]$StartTime = Get-Date;
        CTXOE\Invoke-CTXOEPlugin -PluginName $($m_Action.Plugin) -Params $m_Action.$m_ParamsElementName -Mode $PluginMode -Verbose

        # Test if there is custom details message for current mode or general custom message. This allows you to display friendly message instead of generic error.
        # This can be either mode-specific or generic (message_analyze_true or message_true). Last token (true/false) is used to identify if custom message should be displayed for success or failure
        # If custom message is detected, output from previous function is ignored and CTXOE_Details is replaced with custom text
        [string]$m_OverrideOutputMessageMode = "message_$($PluginMode.ToLower())_$($Global:CTXOE_Result.ToString().ToLower())";
        [string]$m_OverrideOutputMessageGeneric = "message_$($Global:CTXOE_Result.ToString().ToLower())";

        If ($m_Entry.$m_OverrideOutputMessageMode -is [Object]) {
            $Global:CTXOE_Details = $($m_Entry.$m_OverrideOutputMessageMode);
        } ElseIf ($m_Entry.$m_OverrideOutputMessageGeneric -is [Object]) {
            $Global:CTXOE_Details = $($m_Entry.$m_OverrideOutputMessageGeneric);
        }

		# This code is added to have a situation where CTXOE_Result is set, but not to boolean value (for example to empty string). This will prevent engine from crashing and report which entry does not behave as expected.
		# We do this check here so following code does not need to check if returned value exists
		If ($Global:CTXOE_Result -isnot [Boolean]) {
			$Global:CTXOE_Result = $false;
			$Global:CTXOE_Details = "While processing $($m_Entry.Name) from group $($m_Group.ID), there was an error or code did not return expected result. This value should be boolean, while returned value is $($Global:CTXOE_Result.GetType().FullName)."; 
		}

        If ($Global:CTXOE_Result -eq $false) {
            $Run_Status_Failed += 1;
            Write-Host -ForegroundColor Red $CTXOE_Details
        } Else {
            $Run_Status_Success += 1;
            Write-Host -ForegroundColor Green $CTXOE_Details
        }

        # Save information about changes as an element
        CTXOE\New-CTXOEHistoryElement -Element $m_Entry -SystemChanged $CTXOE_SystemChanged -StartTime $StartTime -Result $CTXOE_Result -Details $CTXOE_Details -RollbackInstructions $CTXOE_ChangeRollbackParams

        If ($OptimizerUI) {
            $history = New-Object -TypeName PSObject
            $history.PSObject.TypeNames.Insert(0,"history")
            $history | Add-Member -MemberType NoteProperty -Name GroupID -Value $m_Group.ID
            $history | Add-Member -MemberType NoteProperty -Name EntryName -Value $m_Entry.Name
            $history | Add-Member -MemberType NoteProperty -Name SystemChanged -Value $m_Entry.SystemChanged
            $history | Add-Member -MemberType NoteProperty -Name StartTime -Value $m_Entry.History.StartTime
            $history | Add-Member -MemberType NoteProperty -Name EndTime -Value $m_Entry.History.EndTime
            $history | Add-Member -MemberType NoteProperty -Name Result -Value $m_Entry.History.Return.Result
            $history | Add-Member -MemberType NoteProperty -Name Details -Value $m_Entry.History.Return.Details

            Write-Output $history
        }
    }
}

#Region "Run status processing"
# Finish processing of run_status, save everything to return XML file
$Run_Status.time_end = [DateTime]::Now.ToString('yyyy-MM-dd_HH-mm-ss') # Saving DateTime in predefined format. This is required, since we don't know the target localization settings and want to make sure that UI and engine can communicate in same language.

$Run_Status.entries_success = $Run_Status_Success.ToString();
$Run_Status.entries_failed = $Run_Status_Failed.ToString();

# Run status should be determined ONLY if template has not aborted execution before.
If ($Run_Status.run_details -eq $Run_Status_Default_Message) {
    
    # Count all entries that were expected to execute (execute=1), but have not finished successfully (result!=1)
    [Int]$m_EntriesNotExecuted = $PackDefinitionXml.SelectNodes("//entry[execute=1 and not(history/return/result=1)]").Count

    # If we have entries that are not successful
    If ($m_EntriesNotExecuted -gt 0) {
        If ($m_EntriesNotExecuted -eq 1) {
            $Run_Status.run_details = "$m_EntriesNotExecuted entry has failed";
        } Else {
            $Run_Status.run_details = "$m_EntriesNotExecuted entries have failed";
        }
    # If anything is marked as failed
    } ElseIf ($Run_Status_Failed -gt 0) {
        If ($Run_Status_Failed -eq 1) {
            $Run_Status.run_details = "$Run_Status_Failed entry from this template failed";
        } Else {
            $Run_Status.run_details = "$Run_Status_Failed entries from this template failed";
        }
    # If nothing was actually executed
    } ElseIf ($Run_Status_Success -eq 0) {
        $Run_Status.run_details = "No entries from this template have been processed";
    # Nothing failed, something was successful = sounds good
    } ElseIf ($Run_Status_Success -gt 0 -and $Run_Status_Failed -eq 0) {
        $Run_Status.run_successful = $True.ToString();
        $Run_Status.run_details = "Template has been processed successfully";
    } Else {
        $Run_Status.run_details = "Unknown condition when evaluating run result";  
    }
}
#EndRegion

# Send the overall execute result for UI to show
If ($OptimizerUI) {
    $overallresult = New-Object -TypeName PSObject
    $overallresult.PSObject.TypeNames.Insert(0,"overallresult")
    $overallresult | Add-Member -MemberType NoteProperty -Name run_successful -Value $Run_Status.run_successful
    $overallresult | Add-Member -MemberType NoteProperty -Name run_details -Value $Run_Status.run_details
    $overallresult | Add-Member -MemberType NoteProperty -Name entries_success -Value $Run_Status.entries_success
    $overallresult | Add-Member -MemberType NoteProperty -Name entries_failed -Value $Run_Status.entries_failed

    Write-Output $overallresult
}
# end

# Save the output in XML format for further parsing\history
$PackDefinitionXml.Save($ResultsXml);

#Region "Registry status reporting"

# If mode is 'execute', then save registry status. If mode is 'rollback' (and registry status exists), remove it. No action required for 'analyze' mode

[String]$m_RegistryPath = "HKLM:\SOFTWARE\Citrix\Optimizer\" + $PackDefinitionXml.root.metadata.category;

If ($PluginMode -eq "execute") {
    # Check if registry key exists
    If ($(Test-Path $m_RegistryPath) -eq $False) {
        # If registry key doesn't exist, create it
        New-Item -Path $m_RegistryPath -Force | Out-Null;
    }

    # Save location of XML file that contains more details about execution
    New-ItemProperty -Path $m_RegistryPath -Name "log_path" -PropertyType "string" -Value $ResultsXml -Force | Out-Null;

    # Save all <metadata /> and <run_status />
    ForEach ($m_Node in $PackDefinitionXml.root.metadata.SelectNodes("*")) {
        New-ItemProperty -Path $m_RegistryPath -Name $m_Node.Name -PropertyType "string" -Value $m_Node.InnerText -Force | Out-Null;
    }
    ForEach ($m_Node in $PackDefinitionXml.root.run_status.SelectNodes("*")) {
        New-ItemProperty -Path $m_RegistryPath -Name $m_Node.Name -PropertyType "string" -Value $m_Node.InnerText -Force | Out-Null;
    }

} ElseIf ($PluginMode -eq "rollback") {
    # Check if registry key exists
    If ($(Test-Path $m_RegistryPath) -eq $True) {
        # If registry key exists, delete it
        Remove-Item -Path $m_RegistryPath -Force | Out-Null;
    }
}
#EndRegion

# Use transformation file to generate HTML report
$XSLT = New-Object System.Xml.Xsl.XslCompiledTransform;
$XSLT.Load("$CTXOE_Main\CtxOptimizerReport.xslt");
$XSLT.Transform($ResultsXml, $OutputHtml);

# If another location is requested, save the XML file here as well.
If ($OutputXml.Length -gt 0) {
    $PackDefinitionXml.Save($OutputXml);
}

# If the current host is transcribing, save the transcription
Try {
    Stop-Transcript | Out-Null
} Catch { Write-Host "An exception happened when stopping transcription: $_" -ForegroundColor Red }

# SIG # Begin signature block
# MIIcEQYJKoZIhvcNAQcCoIIcAjCCG/4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCxGYj2XmtJEZwJ
# 3RYO8285U9qf0ByLRqyXLzLZOIjv5aCCCpcwggUwMIIEGKADAgECAhAECRgbX9W7
# ZnVTQ7VvlVAIMA0GCSqGSIb3DQEBCwUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNV
# BAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0xMzEwMjIxMjAwMDBa
# Fw0yODEwMjIxMjAwMDBaMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2Vy
# dCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lD
# ZXJ0IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0EwggEiMA0GCSqGSIb3
# DQEBAQUAA4IBDwAwggEKAoIBAQD407Mcfw4Rr2d3B9MLMUkZz9D7RZmxOttE9X/l
# qJ3bMtdx6nadBS63j/qSQ8Cl+YnUNxnXtqrwnIal2CWsDnkoOn7p0WfTxvspJ8fT
# eyOU5JEjlpB3gvmhhCNmElQzUHSxKCa7JGnCwlLyFGeKiUXULaGj6YgsIJWuHEqH
# CN8M9eJNYBi+qsSyrnAxZjNxPqxwoqvOf+l8y5Kh5TsxHM/q8grkV7tKtel05iv+
# bMt+dDk2DZDv5LVOpKnqagqrhPOsZ061xPeM0SAlI+sIZD5SlsHyDxL0xY4PwaLo
# LFH3c7y9hbFig3NBggfkOItqcyDQD2RzPJ6fpjOp/RnfJZPRAgMBAAGjggHNMIIB
# yTASBgNVHRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAK
# BggrBgEFBQcDAzB5BggrBgEFBQcBAQRtMGswJAYIKwYBBQUHMAGGGGh0dHA6Ly9v
# Y3NwLmRpZ2ljZXJ0LmNvbTBDBggrBgEFBQcwAoY3aHR0cDovL2NhY2VydHMuZGln
# aWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNydDCBgQYDVR0fBHow
# eDA6oDigNoY0aHR0cDovL2NybDQuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJl
# ZElEUm9vdENBLmNybDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0Rp
# Z2lDZXJ0QXNzdXJlZElEUm9vdENBLmNybDBPBgNVHSAESDBGMDgGCmCGSAGG/WwA
# AgQwKjAoBggrBgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAK
# BghghkgBhv1sAzAdBgNVHQ4EFgQUWsS5eyoKo6XqcQPAYPkt9mV1DlgwHwYDVR0j
# BBgwFoAUReuir/SSy4IxLVGLp6chnfNtyA8wDQYJKoZIhvcNAQELBQADggEBAD7s
# DVoks/Mi0RXILHwlKXaoHV0cLToaxO8wYdd+C2D9wz0PxK+L/e8q3yBVN7Dh9tGS
# dQ9RtG6ljlriXiSBThCk7j9xjmMOE0ut119EefM2FAaK95xGTlz/kLEbBw6RFfu6
# r7VRwo0kriTGxycqoSkoGjpxKAI8LpGjwCUR4pwUR6F6aGivm6dcIFzZcbEMj7uo
# +MUSaJ/PQMtARKUT8OZkDCUIQjKyNookAv4vcn4c10lFluhZHen6dGRrsutmQ9qz
# sIzV6Q3d9gEgzpkxYz0IGhizgZtPxpMQBvwHgfqL2vmCSfdibqFT+hKUGIUukpHq
# aGxEMrJmoecYpJpkUe8wggVfMIIER6ADAgECAhAOGlQy3aSxuzh9+Edg24d6MA0G
# CSqGSIb3DQEBCwUAMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0
# IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0EwHhcNMjEwNTAzMDAwMDAw
# WhcNMjMwNTA4MjM1OTU5WjCBnDELMAkGA1UEBhMCVVMxEDAOBgNVBAgTB0Zsb3Jp
# ZGExGDAWBgNVBAcTD0ZvcnQgTGF1ZGVyZGFsZTEdMBsGA1UEChMUQ2l0cml4IFN5
# c3RlbXMsIEluYy4xIzAhBgNVBAsTGlhlbkFwcChTZXJ2ZXIgU0hBMjU2KSAyMDIx
# MR0wGwYDVQQDExRDaXRyaXggU3lzdGVtcywgSW5jLjCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBALmr0y+mHreXSAA2h52drxK+ZZbqY9VPDzIjXpeSv29Y
# ruVL66mVPzZlTxv2FbTgNJWKx/coIGiwfARFo8hAlOBcE/leX4C5Oa+dZmBAJ/0d
# HVc0Rqpz5niAMub10TGBK98WxzhGex9un5gDlPDku2O7LUu7A/+fC5X4QIWEmb3V
# kGxwxxJQtYi8A6X+lf42mQclQENDd9Ay1FCaq4FxlXPaciZRqKPiwYwaAKUStJVQ
# wOSsnkY3xDdDlvkBqv5A846hIc3XiGhyJxW0wAMkSVD+0sJIrrbmro7KlQzpH665
# mEoiUbBgqpioRUcsBYjFXu1E3YsX8il9aXiNS1QVUNsCAwEAAaOCAcQwggHAMB8G
# A1UdIwQYMBaAFFrEuXsqCqOl6nEDwGD5LfZldQ5YMB0GA1UdDgQWBBQ2oqn3et2o
# U23Hw5YtQaIwyGFVxjAOBgNVHQ8BAf8EBAMCB4AwEwYDVR0lBAwwCgYIKwYBBQUH
# AwMwdwYDVR0fBHAwbjA1oDOgMYYvaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL3No
# YTItYXNzdXJlZC1jcy1nMS5jcmwwNaAzoDGGL2h0dHA6Ly9jcmw0LmRpZ2ljZXJ0
# LmNvbS9zaGEyLWFzc3VyZWQtY3MtZzEuY3JsMEsGA1UdIAREMEIwNgYJYIZIAYb9
# bAMBMCkwJwYIKwYBBQUHAgEWG2h0dHA6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAI
# BgZngQwBBAEwgYQGCCsGAQUFBwEBBHgwdjAkBggrBgEFBQcwAYYYaHR0cDovL29j
# c3AuZGlnaWNlcnQuY29tME4GCCsGAQUFBzAChkJodHRwOi8vY2FjZXJ0cy5kaWdp
# Y2VydC5jb20vRGlnaUNlcnRTSEEyQXNzdXJlZElEQ29kZVNpZ25pbmdDQS5jcnQw
# DAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAQEAiWDf0ySwr++GdHl3jXW4
# s426V/lhDVZbXSAjeg40Qpo6pDmjFS2isPRRkvScMCCLhOSwx44HvQRmf78KWxLX
# DbQK5ur6puvSpKA1yhoGOBx9QAAlBDq0/nKu30eH3MXfLq9R7iODhOcrxCQF56za
# 3UggFQQerf/ccZnOVHyEJnv5A+Ajh9NfgmB5YgQ3kIgV+m2fqVWnKXRVC1zTXasG
# x7TdDklhzPjVxv+YyMUUVosuLD0tAgeFKYxwUdfpkOW44u7RPRu2b6o4N4+4g7ny
# ZXtchHOwifKgo98l33QBBNEGaHg6cBe/6MG6fJpD+dDik6yE8Tf0hje/fPH6W7Xw
# 3TGCENAwghDMAgEBMIGGMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2Vy
# dCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lD
# ZXJ0IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0ECEA4aVDLdpLG7OH34
# R2Dbh3owDQYJYIZIAWUDBAIBBQCggdAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcC
# AQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIE
# IHyBWT79BgDfft98Za9u0FquqptSvJu9jMonPrYcyA9JMGQGCisGAQQBgjcCAQwx
# VjBUoDiANgBDAGkAdAByAGkAeAAgAFMAdQBwAHAAbwByAHQAYQBiAGkAbABpAHQA
# eQAgAFQAbwBvAGwAc6EYgBZodHRwOi8vd3d3LmNpdHJpeC5jb20gMA0GCSqGSIb3
# DQEBAQUABIIBAAKH12cINyKh/aJl2Xad9eyE3w9Ach9C8uZAcfpaTHVK6xc5A/BK
# I41w0Q1Moicfdee+a5zQ2Rn6+X5AKJNwYMUk68q7WiHLHMrPtbu6gTkj0gU8iFW4
# wVvjw+0CdtVcwB+QhE5oulTvpBrYp0EZ9bTE/TkQqemkOi4R/ayBBp3uLNy3j8/i
# vCUrlui/E4GauM06YEWxwaOtfJPKQnZCESV6zpODnuRWcLnWcOcImYodkSFPnHcn
# XvPlfm/qI+VamHE/dg3KOBmSBOlgjbNVm8DrX6bW61SQkdpE13uMr4Zgnu/akHNk
# dd4cuTMKSIFXOftblkktSven8jRvuHofj+ahgg5HMIIOQwYKKwYBBAGCNwMDATGC
# DjMwgg4vBgkqhkiG9w0BBwKggg4gMIIOHAIBAzEPMA0GCWCGSAFlAwQCAQUAMIHS
# BgsqhkiG9w0BCRABBKCBwgSBvzCBvAIBAQYEKgMEBTAxMA0GCWCGSAFlAwQCAQUA
# BCCwklp4b1y1lOElBhDoFmMRLbGY7dMZ+o13AnaEQhG6OAIHBdmW8MAo2RgPMjAy
# MjAzMDcwMTM5NTFaoGSkYjBgMQswCQYDVQQGEwJVUzEdMBsGA1UEChMUQ2l0cml4
# IFN5c3RlbXMsIEluYy4xDTALBgNVBAsTBEdMSVMxIzAhBgNVBAMTGkNpdHJpeCBU
# aW1lc3RhbXAgUmVzcG9uZGVyoIIKXTCCBSQwggQMoAMCAQICEAqSXSRVgDYm4Yeg
# BXCaJZAwDQYJKoZIhvcNAQELBQAwcjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERp
# Z2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMo
# RGlnaUNlcnQgU0hBMiBBc3N1cmVkIElEIFRpbWVzdGFtcGluZyBDQTAeFw0xODA4
# MDEwMDAwMDBaFw0yMzA5MDEwMDAwMDBaMGAxCzAJBgNVBAYTAlVTMR0wGwYDVQQK
# ExRDaXRyaXggU3lzdGVtcywgSW5jLjENMAsGA1UECxMER0xJUzEjMCEGA1UEAxMa
# Q2l0cml4IFRpbWVzdGFtcCBSZXNwb25kZXIwggEiMA0GCSqGSIb3DQEBAQUAA4IB
# DwAwggEKAoIBAQDY1rSeHnKVXwd+GJ8X2Db29UadiWwbufxvQaHvGhAUHNs4nVvN
# qLrGa149kA9qlANRHvJ6KLdShnEHWNFs820iFOyh3jweSmhElo7R1SdwVulvavlN
# uJtnTw/6GjcRseg7Q+zNDZTASEWSqO2jSLESJR5IO8JzUM6otI05MwTu0t+IaJWq
# oX7kIKpICqhpnKEiF1ajZhBWlPuZKWBaqTKOsdbEgIH4DRHCIBo54/Mc3VNa54eo
# jWDMTrfILjFpNs/iijW7sR+mCwAPVQWFuNe2X9ed/+S+Ho7scVIQqdNyZKFCFo0k
# Y895tuBw/SvDUoCdAHQ6TRPGT5iCQjBYvRWHAgMBAAGjggHGMIIBwjAfBgNVHSME
# GDAWgBT0tuEgHf4prtLkYaWyoiWyyBc1bjAdBgNVHQ4EFgQUtWN+wIV1Bz2mLr0v
# 0lLFhRYrEm0wDAYDVR0TAQH/BAIwADAOBgNVHQ8BAf8EBAMCB4AwFgYDVR0lAQH/
# BAwwCgYIKwYBBQUHAwgwTwYDVR0gBEgwRjA3BglghkgBhv1sBwEwKjAoBggrBgEF
# BQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzALBglghkgBhv1sAxUw
# cQYDVR0fBGowaDAyoDCgLoYsaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL3NoYTIt
# YXNzdXJlZC10cy5jcmwwMqAwoC6GLGh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9z
# aGEyLWFzc3VyZWQtdHMuY3JsMIGFBggrBgEFBQcBAQR5MHcwJAYIKwYBBQUHMAGG
# GGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBPBggrBgEFBQcwAoZDaHR0cDovL2Nh
# Y2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0U0hBMkFzc3VyZWRJRFRpbWVzdGFt
# cGluZ0NBLmNydDANBgkqhkiG9w0BAQsFAAOCAQEAa0OLR4Hbt+5mnZmDC+iJH2/G
# zVqK4rYqBnK5VX7DBBnSzSwLD2KqzKPZmZjcykxO1FcxlXcG/gn8/SEXw+oZiuoY
# RLqJvlzcwvCxkN6O1NnnXmBf8biHBWQMJkJ1zqFZeMg1iq38mpTiDvcKUOmw1e39
# Aj2vI90I9njSdrtqip0RPseSM/I+ZbI0HnnyK4hlR3du0fd2otJYvVmTE/SijgJN
# OkdGdKshu9I14aFKeDq+XJb+ZplSYJsa9YTI1YO7/eVhmOdKdvnH4ai5VYrtnLtC
# woN9SFG9JW02DW4GNXnGtnK/BdKaVZ67eeWFX29TPNIbo/Q3mGI3hUipHDfusTCC
# BTEwggQZoAMCAQICEAqhJdbWMht+QeQF2jaXwhUwDQYJKoZIhvcNAQELBQAwZTEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTEkMCIGA1UEAxMbRGlnaUNlcnQgQXNzdXJlZCBJRCBSb290
# IENBMB4XDTE2MDEwNzEyMDAwMFoXDTMxMDEwNzEyMDAwMFowcjELMAkGA1UEBhMC
# VVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0
# LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElEIFRpbWVzdGFt
# cGluZyBDQTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAL3QMu5LzY9/
# 3am6gpnFOVQoV7YjSsQOB0UzURB90Pl9TWh+57ag9I2ziOSXv2MhkJi/E7xX08Ph
# fgjWahQAOPcuHjvuzKb2Mln+X2U/4Jvr40ZHBhpVfgsnfsCi9aDg3iI/Dv9+lfvz
# o7oiPhisEeTwmQNtO4V8CdPuXciaC1TjqAlxa+DPIhAPdc9xck4Krd9AOly3UeGh
# eRTGTSQjMF287DxgaqwvB8z98OpH2YhQXv1mblZhJymJhFHmgudGUP2UKiyn5HU+
# upgPhH+fMRTWrdXyZMt7HgXQhBlyF/EXBu89zdZN7wZC/aJTKk+FHcQdPK/P2qwQ
# 9d2srOlW/5MCAwEAAaOCAc4wggHKMB0GA1UdDgQWBBT0tuEgHf4prtLkYaWyoiWy
# yBc1bjAfBgNVHSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzASBgNVHRMBAf8E
# CDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAKBggrBgEFBQcDCDB5
# BggrBgEFBQcBAQRtMGswJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0
# LmNvbTBDBggrBgEFBQcwAoY3aHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0Rp
# Z2lDZXJ0QXNzdXJlZElEUm9vdENBLmNydDCBgQYDVR0fBHoweDA6oDigNoY0aHR0
# cDovL2NybDQuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNy
# bDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJl
# ZElEUm9vdENBLmNybDBQBgNVHSAESTBHMDgGCmCGSAGG/WwAAgQwKjAoBggrBgEF
# BQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzALBglghkgBhv1sBwEw
# DQYJKoZIhvcNAQELBQADggEBAHGVEulRh1Zpze/d2nyqY3qzeM8GN0CE70uEv8rP
# AwL9xafDDiBCLK938ysfDCFaKrcFNB1qrpn4J6JmvwmqYN92pDqTD/iy0dh8GWLo
# XoIlHsS6HHssIeLWWywUNUMEaLLbdQLgcseY1jxk5R9IEBhfiThhTWJGJIdjjJFS
# LK8pieV4H9YLFKWA1xJHcLN11ZOFk362kmf7U2GJqPVrlsD0WGkNfMgBsbkodbeZ
# Y4UijGHKeZR+WfyMD+NvtQEmtmyl7odRIeRYYJu6DC0rbaLEfrvEJStHAgh8Sa4T
# tuF8QkIoxhhWz0E0tmZdtnR79VYzIi8iNrJLokqV2PWmjlIxggLOMIICygIBATCB
# hjByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQL
# ExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFzc3Vy
# ZWQgSUQgVGltZXN0YW1waW5nIENBAhAKkl0kVYA2JuGHoAVwmiWQMA0GCWCGSAFl
# AwQCAQUAoIIBGDAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcN
# AQkEMSIEIBU6AMVZF0M/hktZBZmr6LuBpkNTD6EFpOyQJsnVqvVCMIHIBgsqhkiG
# 9w0BCRACLzGBuDCBtTCBsjCBrwQgsCrO26Gy12Ws1unFBnpWG9FU4YUyDBzPXmMm
# tqVvLqMwgYowdqR0MHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0
# IFNIQTIgQXNzdXJlZCBJRCBUaW1lc3RhbXBpbmcgQ0ECEAqSXSRVgDYm4YegBXCa
# JZAwDQYJKoZIhvcNAQEBBQAEggEAciKZEsBI8NADGBK9V53QCZoqGWT9bQRc/RTr
# hOvL17l64nsF5XxyZpCBT8T+O5lWjsyCbGtLvIt6TmVbChQrIJaDgyrIWgbRY9Lv
# SkQbHgfrTjo9PRL5u/0kacabplQaWpTlKbwAX7JPp0JZ2LVTKhnH60h1YaWVte1a
# FXFQ+hRGfvjFj3yAS7whU5oFuijzlkZ/30uAa3JTRXXHedbRwELj+VTLAtyHYQcw
# 5RgwCbzeyUfnI3tEbtO8IYfltC08W4oip5uoE/oNdJ4mNnP18jhOCRMQFX2pGgfZ
# sVWNd5ykbQrI3twUg2ylSYuUzf6aTjrOFURu2jjuAF1UUvMiBw==
# SIG # End signature block
