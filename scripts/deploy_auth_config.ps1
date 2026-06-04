$PROJECT_REF = "jeotfdtmfdyywktktikz"
$TOKEN = "sbp_ab483082e4d387a2ce0f9799d21e77a8f96a1462"

$confirmationHtml = Get-Content -Raw "supabase/templates/confirmation.html"
$recoveryHtml = Get-Content -Raw "supabase/templates/recovery.html"
$emailChangeHtml = Get-Content -Raw "supabase/templates/email_change.html"

$body = @{
    site_url = "https://jeotfdtmfdyywktktikz.supabase.co"
    mailer_templates = @{
        confirmation = @{
            content = $confirmationHtml
            subject = "Confirm Your DanieWatch Account"
        }
        recovery = @{
            content = $recoveryHtml
            subject = "Reset Your DanieWatch Password"
        }
        email_change = @{
            content = $emailChangeHtml
            subject = "Confirm Your New Email for DanieWatch"
        }
    }
} | ConvertTo-Json -Depth 10

$headers = @{
    "Authorization" = "Bearer $TOKEN"
    "Content-Type"  = "application/json"
}

Write-Host "Deploying branded email templates to Supabase project $PROJECT_REF..." -ForegroundColor Cyan

try {
    $response = Invoke-RestMethod -Uri "https://api.supabase.com/v1/projects/$PROJECT_REF/config/auth" -Method Patch -Headers $headers -Body $body
    Write-Host "Success! Email templates updated." -ForegroundColor Green
    $response | Format-List
} catch {
    Write-Error "Failed to update auth config: $_"
    if ($_.Exception.Response) {
        $stream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        Write-Host "Error Response: $($reader.ReadToEnd())" -ForegroundColor Red
    }
}
