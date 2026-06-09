import requests

r2_url = "https://pub-67769310809f40c4ba5a959a9b56152d.r2.dev/90e8e880a59c9be057214739c88cb4a4?token=1781011660"
gd_url = "https://video-downloads.googleusercontent.com/ADGPM2lZg8Bo9dwXLyDffbW8aoi-mobgi_tGGa59sEcHPcQWDvO3jX-MFapDRHvtUtBBfRsfFEdeYZnVrM61cFKwix5lGVBa5SYw0ZTatyzp8vFayWw_ZNygLTRDnwat1AjMRUzF2TKH_ycXOLtpOP2fdK6orDwhTy8VNwDjcDR6ggs6lHDVCJ55FFd4LVKAaM4yz6ya1ogICbfYQi6E9Jz-wQePGP_bwwjIfSuRpeo_JU1W1bCBnio0YRza2uIhac8Cle0vMAxAkOkGqiQigyqqLuJ5pqumOiWEGyTdwjqVDjCXaidD0NCLRE3BcCitMEUc1Q0TDeT9D4XTFL6gGvHrCsxEv_Uq33RD4mLw5Mr4kmHYLMLAAFsky0qhGEXrrdiIr4swI_0G9RizHjkxRGYGVWZGgQzy-prf-iTuhiHIOP7cgkcW1jtmuP6rnGdtyF7FRKLj-CSQr-u9LbaDNbBQWtdfRQIEN3760vycek5afTNoHRyI8kqXsiiBNB_znteeAwL-k5LexE2T-5c-PmfdCuqJ2hYP2kqmO_TzMEchpmFFutzLeM-_BhoSEWycdibEtwTJiXw_1I9Mp1db_f_dQ9Xp_zlZDwbJwpwIpvNYSFPYCkmmm1tGGBqU05j24z28cT_yJZZk1wjq1QFY6Dkhgi9Adnfk57fLZPDKrnC5eaZ6qt0pZltQ3Ed1jDivxGTEaa74OJqY9q6YoHeh8iTUN9GTtGSkOeeszK0gW-uLhTqYhzI5k_pdn4noSDJq1CWVGa9sycwdb5REqEMgLUaI4kuSCdv76YmC7WpD9HXDvmfjuRVci9utooydAmJ6EwNvTd3kzx3ReaKyzp7nMezdl3zF23uStK6p16mOn8DGvlvTz5hpLMo36d_7JnY-h_W7TF6f_678P1N08duKKO6gCL0mU95-EmpMos0-HzoScPvrj1WBDuJYXJO7peLwSRSpAY2xFYRXOfz7GpBUm_kpa1dDDyhZj4Cu-Q6g9zMOykrADC_5d8PdwkqCcJH5ZQd1RKIfhXahDIzSiQF5eFz_rBPjTk1SnZYFpyvPGBYO6LHlIm99DSwl0mh6rqDwpad0hIK4Nrns"

def test_link(name, url, send_peachify):
    headers = {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    }
    if send_peachify:
        headers.update({
            'Referer': 'https://peachify.top/',
            'Origin': 'https://peachify.top',
        })
    try:
        r = requests.head(url, headers=headers, timeout=5)
        print(f"[{name}] (Peachify headers: {send_peachify}) -> Status: {r.status_code}")
    except Exception as e:
        print(f"[{name}] (Peachify headers: {send_peachify}) -> Error: {e}")

print("Testing Cloudflare R2 link:")
test_link("R2 Link", r2_url, send_peachify=True)
test_link("R2 Link", r2_url, send_peachify=False)

print("\nTesting GD direct link:")
test_link("GD Link", gd_url, send_peachify=True)
test_link("GD Link", gd_url, send_peachify=False)
