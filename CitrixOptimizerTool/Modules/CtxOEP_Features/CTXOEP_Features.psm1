# Get-WindowsOptionalFeature is quite slow. Instead of constantly running it, we are using cache to store the current packages in memory. Cache can be invalidated by changing the value of CTXOEFeatures_IsCacheValid to false, in which case it will be automatically reloaded. 
# Cache is NOT inialized when module is loaded. This prevents issues in environments where all modules are loaded at launch (PowerShell v2) and this module is not supported. In such environments, module is initialized, but unsupported cmdlet is never executed.
[Array]$CTXOEFeatures_Cache = @();
$CTXOEFeatures_IsCacheValid = $False;

Function Get-CTXOEFeatures {
    If ($CTXOEFeatures_IsCacheValid -eq $false) {
        $CTXOEFeatures_Cache = Get-WindowsOptionalFeature -Online
    }

    Return $CTXOEFeatures_Cache
}
Function Test-CTXOEFeaturesState ([String]$Name, [String]$State) {
    [Hashtable]$Return = @{}
    $Return.Result = $False; 

    # First test if feature even exists on this machine
    $m_RequestedFeature = $(Get-CTXOEFeatures | Where-Object {$_.FeatureName -eq $Name});

    # If not found, abort execution
    If ($m_RequestedFeature -isnot [Object]) {
        $Return.Details = "Feature $($Name) was not found on this machine";
        $Return.NotFound = $true;
        Return $Return;
    }

    # Check the state of feature
    $Return.LastState = $m_RequestedFeature.State;
    $Return.Result = $m_RequestedFeature.State -eq $State;
    
    # Supported values for requested state is Enable/Disable. However, State has different variations of this (e.g. DisablePending).
    # We are checking if current state begins with requested state.
    If ($m_RequestedFeature.State -like "$State*") {
        $Return.Result = $True;
        $Return.Details = "Feature $Name is set to $State";
    } Else {
        $Return.Details = "Feature $Name should be in state $State, but is $($m_RequestedFeature.State)";
    }

    Return $Return
}

Function Invoke-CTXOEFeaturesExecuteInternal ([Xml.XmlElement]$Params, [Boolean]$RollbackSupported = $False) {
    [Hashtable]$m_Result = Test-CTXOEFeaturesState -Name $Params.Name -State $Params.Value

    # If feature is already configured, no action need to be taken.
    If ($m_Result.Result -eq $true) {
        $Global:CTXOE_Result = $m_Result.Result;
        $Global:CTXOE_Details = $m_Result.Details;
        Return;
    }

    # If feature was not found, return
    If ($m_Result.NotFound) {
        # If feature should be disabled AND does not exists, that's OK. But if other value was configured than DISABLED, it's not OK. 
        $Global:CTXOE_Result = $Params.Value -eq "Disabled"
        $Global:CTXOE_Details = "Feature $($Params.Name) was not found on this machine"
        Return
    }

    # Invalidate cache
    $CTXOEFeatures_IsCacheValid = $False;

    # Set feature to requested state
    Try {
        If ($Params.Value -eq "Disable") {
            Disable-WindowsOptionalFeature -FeatureName $Params.Name -Online -NoRestart | Out-Null;
        } ElseIf ($Params.Value -eq "Enable") {
            Enable-WindowsOptionalFeature -FeatureName $Params.Name -Online -NoRestart | Out-Null;
        } Else {
            Throw "Unsupported value $($Params.Value) requested for feature $($Params.Name)";
        }
    } Catch {
        $Global:CTXOE_Result = $False; 
        $Global:CTXOE_Details = "Failed to change feature $($Params.Name) to state $($Params.State) with following error: $($_.Exception.Message)"; 
        Return
    }

    # Same the last known startup type for rollback instructions
    $Global:CTXOE_SystemChanged = $true;
    If ($RollbackSupported) {
        [Xml.XmlDocument]$m_RollbackElement = CTXOE\ConvertTo-CTXOERollbackElement -Element $Params

        # Rollback has to be hardcoded. This is required to prevent states like "EnablePending" from being saved. The only two supported states should be "Enable" and "Disable"
        If ($m_Result.LastState -like "Enable*") {
            $m_RollbackElement.rollbackparams.value = "Enable";
        } ElseIf ($m_Result.LastState -like "Disable*") {
            $m_RollbackElement.rollbackparams.value = "Disable";
        }
        $Global:CTXOE_ChangeRollbackParams = $m_RollbackElement
    }

    [Hashtable]$m_Result = Test-CTXOEFeaturesState -Name $Params.Name -State $Params.Value
    $Global:CTXOE_Result = $m_Result.Result
    $Global:CTXOE_Details = $m_Result.Details
    

    Return
}

Function Invoke-CTXOEFeaturesAnalyze ([Xml.XmlElement]$Params) {
    [Hashtable]$m_Result = Test-CTXOEFeaturesState -Name $Params.Name -State $Params.Value

    $Global:CTXOE_Result = $m_Result.Result
    $Global:CTXOE_Details = $m_Result.Details

    Return

}

Function Invoke-CTXOEFeaturesExecute ([Xml.XmlElement]$Params) {
    Invoke-CTXOEFeaturesExecuteInternal -Params $Params -RollbackSupported $True
}

Function Invoke-CTXOEFeaturesRollback ([Xml.XmlElement]$Params) {
    Invoke-CTXOEFeaturesExecuteInternal -Params $Params -RollbackSupported $False
}
# SIG # Begin signature block
# MIIcEQYJKoZIhvcNAQcCoIIcAjCCG/4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBwrsnW96LF9Q2v
# 3rvQ5STUpEut8njw0B7sgxiL26nh0KCCCpcwggUwMIIEGKADAgECAhAECRgbX9W7
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
# IOjIF4OuLT5Z3ryIEv8WSmUdgL4gdBxQuW/uKr6WKSlpMGQGCisGAQQBgjcCAQwx
# VjBUoDiANgBDAGkAdAByAGkAeAAgAFMAdQBwAHAAbwByAHQAYQBiAGkAbABpAHQA
# eQAgAFQAbwBvAGwAc6EYgBZodHRwOi8vd3d3LmNpdHJpeC5jb20gMA0GCSqGSIb3
# DQEBAQUABIIBADiGb7yA71tihF958dI03WHohjqFA3X4LJnmSgx2eCsubeQf+ru+
# jreJDrznv6krMz0djlZpDZrSvyWgmHt+zla2Wp9eC4qy9LXl9a/IwzspXqCijHee
# hwjKaOSpyUSYMZQbs0crCTldeByMGZXzNHUtWETHfiLG5EANXjPPhi7avIskTrQk
# hINf21SX2t1SsJI9m+3f8pcmrnakp6BcZL/fyQwgGK1wVkYjIngIk13B+jbcE0/S
# HB+yk77ZTfpI5DoytuXeCtE9K0OnnS+FX+ah9T0udOd5ritESxPLvjA2ihgQBbGf
# 1PY3xaqlekh+ZVeF31Z/NHNyXmG7N12h8U+hgg5HMIIOQwYKKwYBBAGCNwMDATGC
# DjMwgg4vBgkqhkiG9w0BBwKggg4gMIIOHAIBAzEPMA0GCWCGSAFlAwQCAQUAMIHS
# BgsqhkiG9w0BCRABBKCBwgSBvzCBvAIBAQYEKgMEBTAxMA0GCWCGSAFlAwQCAQUA
# BCAqqhVTqchPX2x3cbqsRZgqJXa1jVOl8q4oiBc6DaZ0MQIHBdmW8dLQqRgPMjAy
# MjAzMDcwMTQwMDlaoGSkYjBgMQswCQYDVQQGEwJVUzEdMBsGA1UEChMUQ2l0cml4
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
# AQkEMSIEIJugXD4p/mmqKDQ+zc3TFpBll0IhGH3hvCODRFHQrrnBMIHIBgsqhkiG
# 9w0BCRACLzGBuDCBtTCBsjCBrwQgsCrO26Gy12Ws1unFBnpWG9FU4YUyDBzPXmMm
# tqVvLqMwgYowdqR0MHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0
# IFNIQTIgQXNzdXJlZCBJRCBUaW1lc3RhbXBpbmcgQ0ECEAqSXSRVgDYm4YegBXCa
# JZAwDQYJKoZIhvcNAQEBBQAEggEAvRpTfWuhO1KDNUdnTEWbz+/XH/mGOy6OCEyJ
# 25XbCeAPl7fBiwrLYQ/QTVz9jr3XO/UNCeUoZlWhNjVxYt2jeP3hwIdm1SBP6jfI
# pjt86aam7TDJ4kzUMmHadVPZru67mL3S08c+DPRDrw9PBj56v7WhcZfYMRtQUPYK
# WmT4FeflltrPDxwtiyp0DpcyZeZMxji0FpHGlRhx45dc2mZOG2e+/lgcvo3cZNQn
# vVKddaUhX8qeuvE/PIw6LCNYwcoRB7MyGknqiyLnnMkd+i2sRcu6RCcAaGoH86l0
# Sy2iAkRSeor2uZ/4RVIYaCtWiD/4veGSRG4z0LRYiULKJ2odCQ==
# SIG # End signature block
