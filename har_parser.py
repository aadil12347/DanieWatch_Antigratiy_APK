import re
import sys
import json

def analyze(filepath):
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()

    m3u8_urls = [
        "https://hello.mousedoor.com/B1HhezoiNd7EN9csQCsksQbFO1MT40AeLk4kuYzmbkh5QEyk9qdNuYUyCN9te18PhnIhnysezRW3ZADwOi7yevHjU4492GekVFl61KGa5Tf_Cd_q4nuDjxq7RIy1QKlk6-cM_gIWKb4tGGaebVUjx4D3H6TQ7jjfUhuZTLWr5ujLEpwkzBpjQ6qJmv_P1DOGDuNiZC_69WrThsXXETlXIcFZgrUoseG_hnxtkVrsl0tzbSWqROByKTtznzSkjdXoD-CU_eDT8qBAYH2xPM2C-OqGXDl3v2GlleJx0XtiWXAJolVcUSmPgSImD4stQZohSgWhlnlLQvo-Hk02JQ8nAO5MC1u8kVnFR79PegF2R8hyipijKL7c72-0j4gRI6CpwJk0beOWN9HROz0F9Lc_QF7hL0b6-nhbqAcsZbNJfsrgNHRhv48p5g_gRJXrbydd9t1s3ilRlhBSniWxOEXiBcwhEo3NuTT84MfH7uDUxZgDb1K7Ri1zD-XZ1dOaxzIpvwEbBrQInhHNJFnFaJxCJvFtVE3AfE_kmbKjZ0di_Jqd5CbybDP6zHsh4-3FS6zq7k2GKkXIBtBfIm3wHGl-7J/index.m3u8",
        "https://hello.mousedoor.com/IHRnW1Oqdh3yw-5pZ50mmQx0bXnEY7NvAe7vsBA_JjArU30lJeQuRnGtU9CrKDGpKdIYxK2bFetOtpsUxVysLZYrNzNnxhKTgdmafDXIiEFiX71X1uYJXLn-1EK76qMe1X80Xmvm8x0ZKaP6obKc510K4AguPbnWwxby85xYq0KRG_lGWwZfmsCl-gizr1LwihGLYAJDyDkphZcMR9R5TFuPMY2OJwkclyNyd5keyOZ5XaG5UQv8dPto2mxfXQwRY4PFD_TuDMs3NlfW6llR7vXRj_RAA02bEPmFiBckmQf9L-SMiQT3xWQzkBPQ3Mfy3axJcownyFH8KON6RVxE_LRVig4v1svmFaY_mBZ9YdfZvJ3cR8zs9H9Wjj8ba3y8rOSy4Tsh6PNqEG1YfkkAjPWsOMkDG6cBsvoRn6kD6gUMMPOZ3sEm0XMvjfqoBq12tW5eKWUea9BJWtoF2dzkhKVAnHiIy62k1aMqi11kOf961jbtV5plpdirBQoeTj7lNmDm20Bj44LFdi2Ei1dOJOcBSyIElkqdmjJOebrJ1YHPTqfx5azculkEeYEkJ5Ej2wVFhAvJ0kl7V5SPYFXSiS/index.m3u8",
        "https://lizer123.site/getm3u8/6TQ0BXUN"
    ]
    
    for url in m3u8_urls:
        escaped_url = re.escape(url)
        match = re.search(f'("url":\\s*"{escaped_url}").*?("response":\\s*{{.*?"content":\\s*{{.*?"text":\\s*"(.*?)".*?}})', content, re.DOTALL | re.IGNORECASE)
        
        if match:
            print(f"\n--- M3U8 Content for: {url[:60]}... ---")
            text = match.group(3).replace('\\n', '\n').replace('\\r', '')
            print(text[:300]) # Print first 300 chars
        else:
            print(f"\n--- No response found for {url[:60]}... ---")

if __name__ == '__main__':
    analyze(sys.argv[1])
