# ผมไม่ได้ obfuctor ให้อาจารย์เข้ามาแงะดูเลยนะครับเนี่ย
# by ntdotjsx https://github.com/ntdotjsx
import requests
import time
import re
import isodate
import getpass
from rich.console import Console
from rich.panel import Panel
from rich.progress import Progress, BarColumn, TextColumn, TimeElapsedColumn, SpinnerColumn
from rich.text import Text
from rich.align import Align

console = Console()

# ==================== Credit ====================
credit = Text(justify="center")
credit.append("╔══════════════════════════════════════╗\n", style="bold cyan")
credit.append("║  ", style="bold cyan")
credit.append(" OVEC Video Auto-Complete ", style="bold white")
credit.append("          ║\n", style="bold cyan")
credit.append("║  ", style="bold cyan")
credit.append(" dev by ", style="dim white")
credit.append("ntdotjsx", style="bold magenta")
credit.append("                    ║\n", style="bold cyan")
credit.append("║  ", style="bold cyan")
credit.append(" github.com/ntdotjsx ", style="dim geen")
credit.append("               ║\n", style="bold cyan")
credit.append("╚══════════════════════════════════════╝", style="bold cyan")

console.print()
console.print(Align.center(credit))
console.print()

BASE_URL = "https://cloud.ovec.go.th/vqa_api"

# ==================== Prompt ====================
STUDENT_ID = console.input("[bold yellow]กรอก STUDENT_ID :[/] ").strip()
YOUTUBE_API_KEY = getpass.getpass("กรอก YOUTUBE_API_KEY : ").strip()
# ================================================

# ==================== Config ====================
API_KEY = "ovecktc2025"
QUIZ_SET_ID = 20
STEP = 5
# ================================================

def get_video_id(url):
    match = re.search(r"(?:v=|youtu\.be/)([a-zA-Z0-9_-]{11})", url)
    return match.group(1) if match else None

def get_youtube_duration(video_url):
    video_id = get_video_id(video_url)
    if not video_id:
        return None
    resp = requests.get(
        "https://www.googleapis.com/youtube/v3/videos",
        params={"part": "contentDetails", "id": video_id, "key": YOUTUBE_API_KEY}
    )
    items = resp.json().get("items", [])
    if not items:
        return None
    duration_iso = items[0]["contentDetails"]["duration"]
    return int(isodate.parse_duration(duration_iso).total_seconds())

# Step 1: ดึง video list
console.print("\n[bold cyan]=== Fetching Video List ===[/]")
with console.status("[bold green]กำลังดึงรายการวิดีโอ...[/]", spinner="dots"):
    fetch_response = requests.post(f"{BASE_URL}/video_progress_fetch.php", json={
        "ApiKey": API_KEY,
        "student_id": STUDENT_ID,
        "quiz_set_id": QUIZ_SET_ID
    })
videos = fetch_response.json()["data"]["videos"]
console.print(f"[green]✔[/] พบวิดีโอทั้งหมด [bold]{len(videos)}[/] รายการ\n")

# Step 2: วนทำทุก EP
for i, video in enumerate(videos):
    lesson_contents_id = video["lesson_contents_id"]
    topic_activities_id = video["topic_activities_id"]
    lesson_topics_id = video["lesson_topics_id"]
    video_url = video["lesson_contents_path"]
    is_completed = video["is_completed"]
    title = video["lesson_contents_title"]

    console.print(Panel(
        f"[bold white]{title}[/]",
        title=f"[cyan]EP {i+1}/{len(videos)}[/]",
        border_style="cyan"
    ))

    if is_completed:
        console.print("  [green] success skiped[/]\n")
        continue

    with console.status("[bold yellow]กำลังดึง duration จาก YouTube...[/]", spinner="dots2"):
        VIDEO_DURATION = get_youtube_duration(video_url)

    if not VIDEO_DURATION:
        console.print("  [red] ดึง duration ไม่ได้ ข้ามไป[/]\n")
        continue
    console.print(f"  [dim]Duration: {VIDEO_DURATION} วินาที[/]")

    # Start Watching
    with console.status("[bold blue]กำลัง start watching...[/]", spinner="arc"):
        start_response = requests.post(f"{BASE_URL}/video_progress.php", json={
            "ApiKey": API_KEY,
            "action": "start_watching",
            "student_id": STUDENT_ID,
            "quiz_set_id": QUIZ_SET_ID,
            "lesson_contents_id": lesson_contents_id,
            "topic_activities_id": topic_activities_id,
            "lesson_topics_id": lesson_topics_id,
            "video_url": video_url,
            "video_duration": 0
        })
    start_data = start_response.json()
    session_token = start_data["data"]["session_token"]
    progress_id = start_data["data"]["progress_id"]
    console.print(f"  [dim] session: {session_token[:20]}...[/]")

    # Update Progress
    positions = list(range(5, VIDEO_DURATION, STEP))
    if positions[-1] != VIDEO_DURATION:
        positions.append(VIDEO_DURATION)

    with Progress(
        SpinnerColumn(spinner_name="dots", style="bold magenta"),
        TextColumn("  [bold green]{task.description}[/]"),
        BarColumn(bar_width=35, style="green", complete_style="bold green"),
        TextColumn("[bold]{task.percentage:>3.0f}%[/]"),
        TextColumn("[dim]{task.completed}/{task.total} วิ[/]"),
        TimeElapsedColumn(),
        console=console,
        transient=False,
    ) as progress:
        task = progress.add_task("กำลังดู", total=VIDEO_DURATION)
        for current_position in positions:
            resp = requests.post(f"{BASE_URL}/video_progress.php", json={
                "ApiKey": API_KEY,
                "action": "update_progress",
                "progress_id": progress_id,
                "session_token": session_token,
                "current_position": current_position,
                "video_duration": VIDEO_DURATION,
                "student_id": STUDENT_ID,
                "lesson_contents_id": lesson_contents_id
            })
            progress.update(task, completed=current_position)
            time.sleep(0)

    # Complete Video
    with console.status("[bold yellow] กำลัง complete...[/]", spinner="moon"):
        complete_resp = requests.post(f"{BASE_URL}/video_progress.php", json={
            "ApiKey": API_KEY,
            "action": "complete_video",
            "student_id": STUDENT_ID,
            "progress_id": progress_id,
            "session_token": session_token,
            "quiz_set_id": QUIZ_SET_ID,
            "lesson_contents_id": lesson_contents_id,
            "topic_activities_id": topic_activities_id,
            "lesson_topics_id": lesson_topics_id,
            "video_url": video_url,
            "video_duration": 0
        })
    console.print("  [bold green] Complete![/]\n")

console.print(Panel(
    Align.center("[bold green] เสร็จสิ้นทุก EP แล้ว![/]"),
    border_style="green"
))
input("\nกด Enter เพื่อปิดโปรแกรม...")