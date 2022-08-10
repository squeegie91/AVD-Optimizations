# General function for execution of the plugins. 
Function Invoke-CTXOEPlugin ([String]$PluginName, [System.Xml.XmlElement]$Params, [String]$Mode) {

    [String]$m_FunctionName = "Invoke-CTXOE$($PluginName)$($Mode.ToString())"

    # First test if the required plugin and function is available 
    If ($(Get-Command "$m_FunctionName" -Module CTXOEP_$($PluginName) -ErrorAction SilentlyContinue) -isnot [System.Management.Automation.FunctionInfo]) {
        Throw "Failed to load the required plugin or required function has not been implemented.
        Module: CTXOEP_$($PluginName)
        Function: $m_FunctionName"
    }

    If ($Params -isnot [Object]) {
        Throw "<params /> element is invalid for current entry. Review the definition XML file."
    }

    # Run the plugin with arguments
    & (Get-ChildItem "Function:$m_FunctionName") -Params $Params

}

# Test if registry key (Key + Name) has the required value (Value). Returns a dictionary with two values - [Bool]Result and [String]Details. 
Function Test-CTXOERegistryValue ([String]$Key, [String]$Name, [String]$Value) {
    # Initialize $return object and always assume failure
    [Hashtable]$Return = @{}
    $Return.Result = $False

    [Boolean]$m_RegKeyExists = Test-Path Registry::$($Key)

    # If value is CTXOE_DeleteKey, check if key itself exists. We need to process this first, because DeleteKey does not require 'Name' parameter and next section would fail
    If ($Value -eq "CTXOE_DeleteKey") {
        $Return.Result = $m_RegKeyExists -eq $False;
        If ($Return.Result -eq $True) {
            $Return.Details = "Registry key does not exist";
        } Else {
            $Return.Details = "Registry key exists";
        }
        Return $Return;
    }

    # If value name ('name') is not defined, Optimizer will only test if key exists. This is used in scenarios where you only need to create registry key, but without any values.
    If ($Name.Length -eq 0) {
        $Return.Result = $m_RegKeyExists;
        If ($Return.Result -eq $True) {
            $Return.Details = "Registry key exists";
        } Else {
            $Return.Details = "Registry key does not exist";
        }
        Return $Return;
    }

    # Retrieve the registry item
    $m_RegObject = Get-ItemProperty -Path Registry::$($Key) -Name $Name -ErrorAction SilentlyContinue;

    # If value is CTXOE_DeleteValue (or legacy CTXOE_NoValue), check if value exists. This code doesn't care what is the actual value data, only if it exists or not.
    If (($Value -eq "CTXOE_NoValue") -or ($Value -eq "CTXOE_DeleteValue")) {
        $Return.Result = $m_RegObject -isnot [System.Management.Automation.PSCustomObject];
        If ($Return.Result -eq $True) {
            $Return.Details = "Registry value does not exist";
        } Else {
            $Return.Details = "Registry value exists";
        }
        Return $Return;
    }

    # Return false if registry value was not found
    If ($m_RegObject -isnot [System.Management.Automation.PSCustomObject]) {
        $Return.Details = "Registry value does not exists"
        Return $Return;
    }

    # Registry value can be different object types, for example byte array or integer. The problem is that PowerShell does not properly compare some object types, for example you cannot compare two byte arrays. 
    # When we force $m_Value to always be [String], we have more predictable comparison operation. For example [String]$([Byte[]]@(1,1,1)) -eq $([Byte[]]@(1,1,1)) will work as expected, but $([Byte[]]@(1,1,1)) -eq $([Byte[]]@(1,1,1)) will not
    [string]$m_Value = $m_RegObject.$Name; 

    # If value is binary array, we need to convert it to string first
    If ($m_RegObject.$Name -is [System.Byte[]]) {
        [Byte[]]$Value = $Value.Split(",");
    }

    # If value type is DWORD or QWORD, registry object returns decimal value, while template can use both decimal and hexadecimal. If hexa is used in template, convert to decimal before comparison
    If ($Value -like "0x*") {
        # $m_RegObject.$Name can be different types (Int32, UInt32, Int64, UInt64...). Instead of handling multiple If...Else..., just use convert as to make sure that we are comparing apples to apples
        $Value = $Value -as $m_RegObject.$Name.GetType();
    }
    
    # $m_Value is always [String], $Value can be [String] or [Byte[]] array
    If ($m_value -ne $Value) {
        $Return.Details = "Different value ($m_value instead of $Value)"
    } Else {
        $Return.Result = $True
        $Return.Details = "Requested value $Value is configured"
    }
    Return $Return
}

# Set value of a specified registry key. Returns a dictionary with two values - [Bool]Result and [String]Details.
# There are few special values - CTXOE_DeleteKey (delete whole registry key if present), CTXOE_DeleteValue (delete registry value if present) and LEGACY CTXOE_NoValue (use CTXOE_DeleteValue instead, this was original name)
Function Set-CTXOERegistryValue ([String]$Key, [String]$Name, [String]$Value, [String]$ValueType) {
    
    [Hashtable]$Return = @{"Result" = $False; "Details" = "Internal error in function"}; 

    [Boolean]$m_RegKeyExists = Test-Path Registry::$Key;

    # First we need to handle scenario where whole key should be deleted
    If ($Value -eq "CTXOE_DeleteKey") {
        If ($m_RegKeyExists -eq $True) {
            Remove-Item -Path Registry::$Key -Force -ErrorAction SilentlyContinue | Out-Null
        }

        # Test if registry key exists or not. We need to pass value, so test function understands that we do NOT expect to find anything at target location
        [Hashtable]$Return = Test-CTXOERegistryValue -Key $Key -Value $Value;

        # When we delete whole registry key, we cannot restore it (unless we completely export it before, which is not supported yet)
        $Return.OriginalValue = "CTXOE_DeleteKey";

        Return $Return;

    }
    
    # If parent registry key does not exists, create it
    If ($m_RegKeyExists -eq $False) {
        New-Item Registry::$Key -Force | Out-Null;
        $Return.OriginalValue = "CTXOE_DeleteKey";
    }

    # If 'Name' is not defined, we need to only create a key and not any values
    If ($Name.Length -eq 0) {
        [Hashtable]$Return = Test-CTXOERegistryValue -Key $Key;
        # We need to re-assign this value again - $Return is overwritten by function Test-CTXOERegistryValue
        If ($m_RegKeyExists -eq $False) {
            $Return.OriginalValue = "CTXOE_DeleteKey";
        }
        Return $Return;
    }

    # Now change the value
    $m_ExistingValue = Get-ItemProperty -Path Registry::$Key -Name $Name -ErrorAction SilentlyContinue
    Try {
        If (($Value -eq "CTXOE_NoValue") -or ($Value -eq "CTXOE_DeleteValue")) {
            Remove-ItemProperty -Path Registry::$Key -Name $Name -Force -ErrorAction SilentlyContinue | Out-Null
        } Else {
            # If value type is binary, we need to convert string to byte array first. If this method is used directly with -Value argument (one line instead of two), it fails with error "You cannot call a method on a null-valued expression."
            If ($ValueType -eq "Binary") {
                [Byte[]]$m_ByteArray = $Value.Split(","); #[System.Text.Encoding]::Unicode.GetBytes($Value);
                New-ItemProperty -Path Registry::$Key -Name $Name -PropertyType $ValueType -Value $m_ByteArray -Force | Out-Null
            } Else {
                New-ItemProperty -Path Registry::$Key -Name $Name -PropertyType $ValueType -Value $Value -Force | Out-Null
            }
        }
    } Catch {
        $Return.Details = $($_.Exception.Message); 
        $Return.OriginalValue = "CTXOE_DeleteValue";
        Return $Return; 
    }

    # Re-run the validation test again
    [Hashtable]$Return = Test-CTXOERegistryValue -Key $Key -Name $Name -Value $Value
    
    # Save previous value for rollback functionality
    If ($m_RegKeyExists -eq $True) {
        If ($m_ExistingValue -is [Object]) {
            $Return.OriginalValue = $m_ExistingValue.$Name
        } Else {
            $Return.OriginalValue = "CTXOE_DeleteValue"
        }
    } Else {
        # We need to set this again, since $Return is overwritten by Test-CTXOERegistryValue function
        $Return.OriginalValue = "CTXOE_DeleteKey";
    }
    
    Return $Return
}
Function ConvertTo-CTXOERollbackElement ([Xml.XmlElement]$Element) {
    # Convert the element to XmlDocument. 
    [Xml]$m_TempXmlDocument = New-Object Xml.XmlDocument

    # Change the <params /> (or <executeparams /> to <rollbackparams />. 
    [Xml.XmlElement]$m_TempRootElement = $m_TempXmlDocument.CreateElement("rollbackparams")
    $m_TempRootElement.InnerXml = $Element.InnerXml
    $m_TempXmlDocument.AppendChild($m_TempRootElement) | Out-Null

    # Rollback is based on <value /> element. If this element doesn't exist already (in $Element), create an empty one. If we don't create this empty element, other functions that are trying to assign data to property .value will fail
    If ($m_TempRootElement.Item("value") -isnot [Xml.XmlElement]) {
        $m_TempRootElement.AppendChild($m_TempXmlDocument.CreateElement("value")) | Out-Null; 
    }

    # Return object
    Return $m_TempXmlDocument
}
Function New-CTXOEHistoryElement ([Xml.XmlElement]$Element, [Boolean]$SystemChanged, [DateTime]$StartTime, [Boolean]$Result, [String]$Details, [Xml.XmlDocument]$RollbackInstructions) {
    # Delete any previous <history /> from $Element
    If ($Element.History -is [Object]) {
        $Element.RemoveChild($Element.History) | Out-Null; 
    }

    # Get the parente XML document of the target element
    [Xml.XmlDocument]$SourceXML = $Element.OwnerDocument

    # Generate new temporary XML document. This is easiest way how to construct more complex XML structures with minimal performance impact. 
    [Xml]$m_TempXmlDoc = "<history><systemchanged>$([Int]$SystemChanged)</systemchanged><starttime>$($StartTime.ToString())</starttime><endtime>$([DateTime]::Now.ToString())</endtime><return><result>$([Int]$Result)</result><details>$Details</details></return></history>"

    # Import temporary XML document (standalone) as an XML element to our existing document
    $m_TempNode = $SourceXML.ImportNode($m_TempXmlDoc.DocumentElement, $true)
    $Element.AppendChild($m_TempNode) | Out-Null; 

    # If $RollbackInstructions is provided, save it as a <rollackparams /> element
    If ($RollbackInstructions -is [Object]) {
        $Element.Action.AppendChild($SourceXML.ImportNode($RollbackInstructions.DocumentElement, $true)) | Out-Null
    }
}

# Function to validate conditions. Returns hashtable object with two properties - Result (boolean) and Details. Result should be $True
Function Test-CTXOECondition([Xml.XmlElement]$Element) {

    [Hashtable]$m_Result = @{}; 

    # Always assume that script will fail
    $m_Result.Result = $False;
    $m_Result.Details = "No condition message defined"

    # $CTXOE_Condition is variable that should be returned by code. Because it is global, we want to reset it first. Do NOT assign $Null to variable - it will not delete it, just create variable with $null value
    Remove-Variable -Force -Name CTXOE_Condition -ErrorAction SilentlyContinue -Scope Global;
    Remove-Variable -Force -Name CTXOE_ConditionMessage -ErrorAction SilentlyContinue -Scope Global;

    # Check if condition has all required information (code is most important)
    If ($Element.conditioncode -isnot [object]) {
        $m_Result.Details = "Invalid or missing condition code. Condition cannot be processed";
        Return $m_Result;
    }

    # Execute code. This code should always return $Global:CTXOE_Condition variable (required) and $Global:CTXOE_ConditionMessage (optional)
    Try {
        Invoke-Expression -Command $Element.conditioncode;
    } Catch {
        $m_Result.Details = "Unexpected failure while processing condition: $($_.Exception.Message)";
        Return $m_Result;
    }
    

    # Validate output

    # Test if variable exists
    If (-not $(Test-Path Variable:Global:CTXOE_Condition)) {
        $m_Result.Details = "Required variable (CTXOE_Condition) NOT returned by condition. Condition cannot be processed";
        Return $m_Result;
    }

    # Test if variable is boolean
    If ($Global:CTXOE_Condition -isnot [Boolean]) {
        $m_Result.Details = "Required variable (CTXOE_Condition) is NOT boolean ($True or $False), but $($Global:CTXOE_Condition.GetType().FullName). Condition cannot be processed";
        Return $m_Result;
    }

    # Assign value to variable
    $m_Result.Result = $Global:CTXOE_Condition;

    # If condition failed and failed message is specified in XML section for condition, assign it
    If ($Element.conditionfailedmessage -is [Object] -and $m_Result.Result -eq $False) {
        $m_Result.Details = $Element.conditionfailedmessage;
    }

    # If $CTXOE_ConditionMessage is returned by code, use it to override the failed message
    If ((Test-Path Variable:Global:CTXOE_ConditionMessage)) {
        $m_Result.Details = $Global:CTXOE_ConditionMessage
    }

    # Return object
    Return $m_Result;

}
# SIG # Begin signature block
# MIIcEQYJKoZIhvcNAQcCoIIcAjCCG/4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAS0hzMzvQXqLta
# 9Aw7XNyqT2YuXmxurP0qFfFUumkmMKCCCpcwggUwMIIEGKADAgECAhAECRgbX9W7
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
# IEoO6cEbzRuuQ5ai4y7juKavIAo4BqkLcPMzsibzvPQeMGQGCisGAQQBgjcCAQwx
# VjBUoDiANgBDAGkAdAByAGkAeAAgAFMAdQBwAHAAbwByAHQAYQBiAGkAbABpAHQA
# eQAgAFQAbwBvAGwAc6EYgBZodHRwOi8vd3d3LmNpdHJpeC5jb20gMA0GCSqGSIb3
# DQEBAQUABIIBAIvXIt2ei2fp7GDkkbljTnJREPffT/CIVbwVf9WLEBzlnJwu2WNK
# 6Zr3VQl4NrdYNjfU8RZxpOdB6HpnJsNG/7lRt1MmoA+peltNHRSXcr+cYBT6ZBiq
# ZWZhoJLVcZdVphiJZjVxPMKjaz+prFj28rHQf63Cywo2bxRV6JYi4hejUB4cB8N1
# XOhmIuACuUuiDuKtWCI3NzY9a5BYHXxavzafY8CmNBccZ3kR1TtRcm67NryNonMD
# Lx5OH/sxPtM4qkFza+ThAT1l7XDGoeamsgZ/j8MDP7Ip3OCaN1vd3JEaYrJjCWBb
# 9svMy2WD0ydyyUiEPQ5abMh2GovHMmkJ4iyhgg5HMIIOQwYKKwYBBAGCNwMDATGC
# DjMwgg4vBgkqhkiG9w0BBwKggg4gMIIOHAIBAzEPMA0GCWCGSAFlAwQCAQUAMIHS
# BgsqhkiG9w0BCRABBKCBwgSBvzCBvAIBAQYEKgMEBTAxMA0GCWCGSAFlAwQCAQUA
# BCCU3+BEgv/zUKWc/Hz0DbahZ8hd/Zr/xi324BmShZ3CeAIHBdmW8zHEuRgPMjAy
# MjAzMDcwMTQwMzJaoGSkYjBgMQswCQYDVQQGEwJVUzEdMBsGA1UEChMUQ2l0cml4
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
# AQkEMSIEILmDqOzHOzJIVqlCgA6GqWnMlBJHrk4qT+FdeFpfZEDuMIHIBgsqhkiG
# 9w0BCRACLzGBuDCBtTCBsjCBrwQgsCrO26Gy12Ws1unFBnpWG9FU4YUyDBzPXmMm
# tqVvLqMwgYowdqR0MHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0
# IFNIQTIgQXNzdXJlZCBJRCBUaW1lc3RhbXBpbmcgQ0ECEAqSXSRVgDYm4YegBXCa
# JZAwDQYJKoZIhvcNAQEBBQAEggEAyuC05v+QwZNSwiPfTQ3j94VEGo/CyjzLoDfv
# Lv+gXijhVHu8IofTd4r43iHy8SQjOKGJilm+XbgAv/u3+B6sl00iFXTLaeTApexN
# /v+TtjJHnxQVmLXjCVQWfGkvZT9NvzZz8HaLq74TWDo0ktXiQ7Dw1DhivHk4FBSd
# dovk3P+YNROJ1HM8qENSQIB0nitd2Ir+LpjLpxOiByn9SF8Pib+SZ+wvj8UODGvn
# 3bxOYRIYLJ2XIcIm1KtDrQCYf7BBttnhr0IbyV3hnMb4ToXPXz66Ko7V6TUpugrY
# MWUMq1oc/DwKIpmqqJdqbJLgOqCCAewY+1E5gkyW0s/d6lyOrw==
# SIG # End signature block
