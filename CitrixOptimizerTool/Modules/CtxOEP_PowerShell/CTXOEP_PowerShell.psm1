﻿Function Invoke-CTXOEPowerShellCommon ([Xml.XmlElement]$Params) {
    Try {
        If ($Params.value -is [System.Xml.XmlElement]) {
            Invoke-Expression -Command $Params.value.InnerText
        } Else {
            Invoke-Expression -Command $Params.value
        }
        
    } Catch {
        $Global:CTXOE_Result = $False;
        $Global:CTXOE_Details = "Unexpected crash of PowerShell code, error message: $($_.Exception)"
    }
}
Function Invoke-CTXOEPowerShellExecute ([Xml.XmlElement]$Params) {
    # Can only assume that system was changed.
    $Global:CTXOE_SystemChanged = $true;
    Invoke-CTXOEPowerShellCommon -Params $Params
}

Function Invoke-CTXOEPowerShellAnalyze ([Xml.XmlElement]$Params) {
    Invoke-CTXOEPowerShellCommon -Params $Params
}

Function Invoke-CTXOEPowerShellRollback ([Xml.XmlElement]$Params) {
    Invoke-CTXOEPowerShellCommon -Params $Params
}
# SIG # Begin signature block
# MIIcEQYJKoZIhvcNAQcCoIIcAjCCG/4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBs50TPZS/2oo49
# YBMHJ2JQmBUt+dWbSSlmrqTp2K1Q2aCCCpcwggUwMIIEGKADAgECAhAECRgbX9W7
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
# IH+fnutGkMugylWpNtVhhJRNt/oQMFg7/s0xI0JX+1ndMGQGCisGAQQBgjcCAQwx
# VjBUoDiANgBDAGkAdAByAGkAeAAgAFMAdQBwAHAAbwByAHQAYQBiAGkAbABpAHQA
# eQAgAFQAbwBvAGwAc6EYgBZodHRwOi8vd3d3LmNpdHJpeC5jb20gMA0GCSqGSIb3
# DQEBAQUABIIBAFxZTe262NCJHBZibBUBnSAKCxTPKoBSRRsLoQr1YlfBbh81OoS4
# 3UiWaTN0/CMUy9xcAsKPwCEJrckjheX6vQvxPBA5SSSWisvHne30W8SEz+4b24XA
# 8TyyFpffFqFJuf/dLe0DgOAe2GiCvpiPrDRvG1X1qSlEvwZU3WVHxZRPsC8ZFIUm
# oy8tgfJzSQcKufVTgB5P1TaFp+LHW4qqNFclmJQRCDmfuDDfiyatPVGYskM79TOM
# uduUpJeMSIZXq4fl0D6xZyiAhebmVABfIinxnQLLXiz0OMdrxTr+foyGVejbgQrj
# TM814w1FO+vZo+mKAYSIpb+5Lb1lmJpU7EGhgg5HMIIOQwYKKwYBBAGCNwMDATGC
# DjMwgg4vBgkqhkiG9w0BBwKggg4gMIIOHAIBAzEPMA0GCWCGSAFlAwQCAQUAMIHS
# BgsqhkiG9w0BCRABBKCBwgSBvzCBvAIBAQYEKgMEBTAxMA0GCWCGSAFlAwQCAQUA
# BCBGIcgYIqtz27qU+vHph7QrIRsf3o2OsmnmWCkCE5o6cQIHBdmW8gCXhhgPMjAy
# MjAzMDcwMTQwMTJaoGSkYjBgMQswCQYDVQQGEwJVUzEdMBsGA1UEChMUQ2l0cml4
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
# AQkEMSIEICMIkcV6mfwdAtLOLcru0mjvfkU6tP7THU3D4kz4BjS7MIHIBgsqhkiG
# 9w0BCRACLzGBuDCBtTCBsjCBrwQgsCrO26Gy12Ws1unFBnpWG9FU4YUyDBzPXmMm
# tqVvLqMwgYowdqR0MHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0
# IFNIQTIgQXNzdXJlZCBJRCBUaW1lc3RhbXBpbmcgQ0ECEAqSXSRVgDYm4YegBXCa
# JZAwDQYJKoZIhvcNAQEBBQAEggEAXGZ2TPurzMDMIsSXJnvOTq4F7YSozQJetkir
# TksXeHyR6eq7DNnFfLW+5BExYLYNQpnP/S+inKjlnI9TSMMRcGPLO8r020twNBjJ
# ZqtBPENnkxFq2QfGd3nJuNBGkTWzGLInUltysGgPDlUv7wj3atXp9in7RjLPraZ6
# txWWrbJ1l4ZR2n8AI8LfqDx09bVZj+hbhrhi7cE0U4QxmTqVUwJNWa5IaL3GNUVZ
# BXLYQEys4Elpihga/vdUdcGKwLXRY4g+yPNaqB38tWBOI5xT5x14gWjuQV20kpb/
# KuEusifPJoe0gH0KxvZQ6Ah0cfO9yAOUIvACF9V34PmTQ3W/KA==
# SIG # End signature block