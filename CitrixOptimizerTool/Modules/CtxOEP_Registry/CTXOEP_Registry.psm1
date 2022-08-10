# This function is used to check if all required XmlElement are defined. Using the .Item() method, because .name would return the name of the parent if element is missing. 
Function Test-CTXOERegistryInput ([Xml.XmlElement]$Params) {
    # 'Path' is the only property that is  required for all registry operations
    If ($Params.Item("path") -isnot [Xml.XmlElement]) {Throw "Required property 'Path' is missing"}; 
    
    # Test if 'Path' contains unsupported ":" character (PSdrive). ":" is supported as part of key name, but not as part of root drive (e.g. 'HKLM:\Software'), so we cannot use simple .Contains() and have to parse the first token instead
    If ($Params.Path.Split("\")[0][-1] -eq ":") {Throw "Registry path includes unsupported ':' character in root key path"};

    # DeleteKey requires only path, but doesn't care about value name. We don't need to validate any other parameters and can exit
    If ($Params.Value -eq "CTXOE_DeleteKey") {Return;}

    # "Name" is just an optional parameter. If it is not specified, Optimizer will just create empty registry key. However if 'Name' is provided, we need to make sure that also 'ValueType' and 'Value' are provided
    If ($Params.Item("name") -is [Xml.XmlElement]) {
        If ($Params.Item("value") -isnot [Xml.XmlElement]) {Throw "Required property Value is missing"};
        If ($Params.Item("valuetype") -isnot [Xml.XmlElement] -and $Params.value -ne "CTXOE_DeleteValue") {Throw "Required property ValueType is missing"};
    } Else {
        If ($Params.Value -eq "CTXOE_DeleteValue") {Throw "Required property Name is missing"};
    }
    
}

Function Invoke-CTXOERegistryAnalyze ([Xml.XmlElement]$Params) {
    Test-CtxOEREgistryInput -Params $Params

    # When modifications are made to default user, we need to load the registry hive file first
    # Since there are few different places where code can be returned in Test-CTXOERegistryValue function, we are handling hive loading here

    [Boolean]$m_IsDefaultUserProfile = $Params.Path -like "HKDU\*" -or $Params.Path -like "HKEY_USERS\DefaultUser\*";

    If ($m_IsDefaultUserProfile) {
            # Mount DefaultUser
            Reg Load "HKU\DefaultUser" "C:\Users\Default\NTUSER.DAT" | Out-Null;
            New-PSDrive -Name DefaultUser -PSProvider Registry -Root HKEY_USERS\DefaultUser | Out-Null;
    
            # Replace HKDU\ with actual registry path
            $Params.Path = $Params.Path -Replace "HKDU\\", "HKEY_USERS\DefaultUser\";
    }

    # Using psbase.InnerText because it's the only way how to handle (optional) XML elements. If we use $Params.Name and 'name' doesn't exist, parent element (params) is used by function instead.
    [Hashtable]$m_Result = CTXOE\Test-CTXOERegistryValue -Key $Params.Path -Name $Params.Item("name").psbase.InnerText -Value $Params.Item("value").psbase.InnerText
    $Global:CTXOE_Result = $m_Result.Result
    $Global:CTXOE_Details = $m_Result.Details

    If ($m_IsDefaultUserProfile) {
        # Unmount DefaultUser
        Remove-PSDrive -Name DefaultUser;
        [GC]::Collect();
        Reg Unload "HKU\DefaultUser" | Out-Null;
    }
    
}

Function Invoke-CTXOERegistryExecuteInternal ([Xml.XmlElement]$Params, [Boolean]$RollbackSupported = $False) {
    Test-CtxOEREgistryInput -Params $Params

    # When modifications are made to default user, we need to load the registry hive file first
    # Since there are few different places where code can be returned in Test-CTXOERegistryValue function, we are handling hive loading here

    [Boolean]$m_IsDefaultUserProfile = $Params.Path -Like "HKDU\*" -or $Params.Path -Like "HKEY_USERS\DefaultUser\*";

    If ($m_IsDefaultUserProfile) {
            # Mount DefaultUser
            Reg Load "HKU\DefaultUser" "C:\Users\Default\NTUSER.DAT" | Out-Null;
            New-PSDrive -Name DefaultUser -PSProvider Registry -Root HKEY_USERS\DefaultUser | Out-Null;
    
            # Replace HKDU\ with actual registry path
            $Params.Path = $Params.Path -Replace "HKDU\\","HKEY_USERS\DefaultUser\";
    }

    # Test if value is already configured or not
    [Hashtable]$m_Result = CTXOE\Test-CTXOERegistryValue -Key $Params.Path -Name $Params.Item("name").psbase.InnerText -Value $Params.Item("value").psbase.InnerText
    
    # If the value is not configured, change it
    If ($m_Result.Result -ne $true) {
        [Hashtable]$m_Result = CTXOE\Set-CTXOERegistryValue -Key $Params.Path -ValueType $Params.Item("valuetype").psbase.InnerText -Value $Params.Item("value").psbase.InnerText -Name $Params.Item("name").psbase.InnerText
        $Global:CTXOE_SystemChanged = $true;
        
        If ($RollbackSupported) {
            [Xml.XmlDocument]$m_RollbackElement = CTXOE\ConvertTo-CTXOERollbackElement -Element $Params
            $m_RollbackElement.rollbackparams.value = $m_Result.OriginalValue.ToString();
            $Global:CTXOE_ChangeRollbackParams = $m_RollbackElement
        }
    }

    $Global:CTXOE_Result = $m_Result.Result
    $Global:CTXOE_Details = $m_Result.Details

    If ($m_IsDefaultUserProfile) {
        # Unmount DefaultUser
        Remove-PSDrive -Name DefaultUser;
        [GC]::Collect();
        Reg Unload "HKU\DefaultUser" | Out-Null;
    }
}

Function Invoke-CTXOERegistryExecute ([Xml.XmlElement]$Params) {
    Invoke-CTXOERegistryExecuteInternal -Params $Params -RollbackSupported $True
}

Function Invoke-CTXOERegistryRollback ([Xml.XmlElement]$Params) {
    Invoke-CTXOERegistryExecuteInternal -Params $Params -RollbackSupported $False
}
# SIG # Begin signature block
# MIIcEQYJKoZIhvcNAQcCoIIcAjCCG/4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAaWVBYDpvDWmbO
# IMpB2coJuHJkcrPaAUEZyKfa3OHGwqCCCpcwggUwMIIEGKADAgECAhAECRgbX9W7
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
# IIQbn83iVyRynmzGfZ3DnhNMB5adN2jiAC6G5REsP6WzMGQGCisGAQQBgjcCAQwx
# VjBUoDiANgBDAGkAdAByAGkAeAAgAFMAdQBwAHAAbwByAHQAYQBiAGkAbABpAHQA
# eQAgAFQAbwBvAGwAc6EYgBZodHRwOi8vd3d3LmNpdHJpeC5jb20gMA0GCSqGSIb3
# DQEBAQUABIIBAJBu59OYZ7LXrmU9eaFCzxJ59Q4p15OJ4W+JNfwD7/ubi6k5v7Bx
# X1+C631nPrfPGJPwTiale6Df95NgJjpqSIKzb5rGdYNL5eaj0weU5yIwj5cmE0wg
# 9K2HsPtb7jvrgoKv7vPJ0wPXKQvP4l6v89dH06bMKEkuXDJzIH2wdjQFXiE6+4AH
# e/r92sCexwc6plR34ZkJ9MT98IUAeRGGqWAyJ5M7i9Zs2EeF0+Q9uCaCJOayovEd
# SXHhga3wOuLY6GlS4XizJ+R7b6Ba+xrwwfZRCxZ/YQ8lohIyd1EDJ//Uzl87tJKK
# YDjxxPKdugPgNoi9j8Wq40LPaNRQUD9Xn4ehgg5HMIIOQwYKKwYBBAGCNwMDATGC
# DjMwgg4vBgkqhkiG9w0BBwKggg4gMIIOHAIBAzEPMA0GCWCGSAFlAwQCAQUAMIHS
# BgsqhkiG9w0BCRABBKCBwgSBvzCBvAIBAQYEKgMEBTAxMA0GCWCGSAFlAwQCAQUA
# BCBvy3TC/8vK2hwJ05/c5N8IVaxuiPzNHaZcZsmU8g/9uAIHBdmW8kzizhgPMjAy
# MjAzMDcwMTQwMTdaoGSkYjBgMQswCQYDVQQGEwJVUzEdMBsGA1UEChMUQ2l0cml4
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
# AQkEMSIEIPXz28cXm6p5gIaCfNypRf0XyExUkRANn5P6aIBnxK5XMIHIBgsqhkiG
# 9w0BCRACLzGBuDCBtTCBsjCBrwQgsCrO26Gy12Ws1unFBnpWG9FU4YUyDBzPXmMm
# tqVvLqMwgYowdqR0MHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0
# IFNIQTIgQXNzdXJlZCBJRCBUaW1lc3RhbXBpbmcgQ0ECEAqSXSRVgDYm4YegBXCa
# JZAwDQYJKoZIhvcNAQEBBQAEggEAtyQp5qRA91djsItZuY9zO/EcXJ2BzPSN9Xnz
# n0cOYQsTzWG1t+813fne8Xm+ErAhHqGpgbYUHisUL2uURH8dsZr73z+ytSi+qXZx
# aWXhdCn+yAavA8mugweu2Aic4ElrpkK5aGHnHLb8zIkXe63wzevuZkPiDQfZNNjn
# 4U/CRaPbiUukCpoWNZLJiNpxaIc/eXBmRnk8jltXchiCMT9JpAmPdi+R8sEM57aT
# 0rYdq2qjxlN72DXR3h2JWhhcu8BIyCYb3IKFrDHU/kWud1yjx0TetMoC5TafuEdr
# bJWRybPVcVO2ac+BPmITpLxUYVCTig1cf7ybW43hCGx3dCfc1w==
# SIG # End signature block
