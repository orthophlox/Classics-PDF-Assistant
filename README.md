# Classics PDF Assistant

스캔한 고전 문헌 PDF(고대 그리스어 / 라틴어 / 영어 혼용)를 연구·아카이빙용으로
정리해 주는 macOS 네이티브 앱입니다. SwiftUI로 작성된 완전한 네이티브 UI와,
무거운 이미지/OCR 처리를 전담하는 Python 백엔드(서브프로세스)로 구성됩니다.

## 기능

1. **자동 디스큐(deskew)** — 스캔 시 기울어진 페이지를 감지해 자동 보정
2. **검색 가능한 PDF로 OCR** — Tesseract(pytesseract)로 그리스어+라틴어+영어
   혼합 인식, 원본 스캔 이미지 위에 보이지 않는 텍스트 레이어를 입힘
3. **텍스트 영역 크롭** — 페이지마다 본문 영역을 자동 감지, 수동 조정 가능
4. **다중 영역 감지 (Critical Edition 지원)** — 본문(main text)뿐 아니라
   하단 비평장치(critical apparatus), 좌/우 여백 행 번호(margin line
   numbers)까지 구분 인식. 기본적으로 본문만 OCR하고 나머지는 제외하지만,
   화면에서 각 영역을 탭해 다른 영역을 크롭 대상으로 바꿀 수 있음
5. **OCR 교정 화면** — 인식된 텍스트를 스캔 원본과 대조하며 확인, 신뢰도가
   낮은 단어는 자동으로 강조 표시되어 바로 수정 가능
6. **일괄(batch) 처리** — 폴더 단위로 여러 PDF를 한 번에 처리
7. **플레인 텍스트(.txt) 내보내기** — 검색 가능한 PDF와 함께 저장
8. **경량 PDF/A 내보내기** — 메타데이터 + ICC 프로파일만 사용 (Ghostscript
   불필요, 완전한 PDF/A 인증은 아니지만 대부분의 장기보존 용도에 충분)
9. **흑백(B&W) 출력 토글** — 출력 이미지를 순수 흑/백으로 이진화해 파일
   용량을 크게 줄임 (OCR 자체는 항상 원본 컬러/그레이스케일로 수행되므로
   인식률에는 영향 없음)
10. **서지정보 기반 자동 리네임** — 타이틀 페이지 OCR에서 저자/제목/연도
    후보를 추출해 `저자 - 제목 (연도).pdf` 형식의 파일명을 제안, 수정 후 적용
11. **Zotero 연동** — 완료된 PDF를 로컬에서 실행 중인 Zotero 데스크톱 앱으로
    한 번에 전송 (API 키/인터넷 불필요)
12. **깔끔한 제거(Clean Uninstall)** — 앱 메뉴의 "Uninstall…"로 설정과 임시
    파일을 정리하거나, dmg에 동봉된 `Uninstall.command`로 앱 자체까지 한
    번에 삭제. 내보낸 PDF 등 사용자 문서는 어느 쪽도 절대 건드리지 않음

## 아키텍처 한눈에 보기

```
┌─────────────────────────────┐    JSON (stdin/stdout)    ┌──────────────────────────────┐
│   SwiftUI 앱 (네이티브 UI)   │ ─────────────────────────>│   Python 백엔드 (서브프로세스)  │
│  가져오기, 크롭 편집,        │<───────────────────────── │   pdf_backend, PyInstaller로   │
│  OCR 교정, 리네임, 내보내기   │   진행 상황 (stderr NDJSON) │   프리징, Tesseract + tessdata │
│                              │                            │   (grc/lat/eng) + OpenCV 포함  │
└─────────────────────────────┘                            └──────────────────────────────┘
```

- UI는 100% 네이티브 SwiftUI/AppKit
- 실제 이미지 처리(OpenCV)와 OCR(Tesseract)은 전부 Python 백엔드가 담당하며,
  Swift는 이를 서브프로세스로 실행하고 JSON으로 통신
- 두 프로세스를 분리한 이유, 왜 한 페이지당 OCR을 한 번만 호출하는지, 다중
  영역 감지 알고리즘, Zotero 연동 방식 등 설계 근거는 전부
  [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)에 정리되어 있습니다.
- Swift ↔ Python 사이에 주고받는 정확한 JSON 스펙은
  [`docs/JSON_PROTOCOL.md`](docs/JSON_PROTOCOL.md)를 참고하세요.

## 저장소 구조

```
Classics-PDF-Assistant/
├── backend/                 # Python 엔진 (pdf_backend) — 독립적으로 테스트/실행 가능
│   ├── pdf_backend/          # deskew, crop, ocr, textlayer, metadata, export, pipeline, cli
│   ├── tests/                 # pytest, 합성 이미지 기반 (실제 스캔본 불필요)
│   └── packaging/             # PyInstaller spec + Tesseract 번들링 스크립트 (macOS 전용)
├── ClassicsPDFAssistant/     # SwiftUI 앱 소스 (Xcode 필요)
│   ├── project.yml            # XcodeGen 스펙 — .xcodeproj는 여기서 생성됨
│   └── ClassicsPDFAssistant/  # App/Models/Backend/Services/Views/Resources
├── docs/
│   ├── ARCHITECTURE.md        # 설계 근거와 각 알고리즘 설명
│   └── JSON_PROTOCOL.md       # Swift ↔ Python 통신 스펙
├── scripts/
│   ├── build_dmg.sh           # 소스 → .app → .dmg 전 과정을 자동화 (macOS 전용)
│   └── Uninstall.command      # dmg에 동봉되는 완전 제거 스크립트 (macOS 전용)
└── .github/workflows/
    └── build-dmg.yml          # GitHub Actions로 .dmg를 자동 빌드 (터미널 없이 다운로드 가능)
```

---

## 맥에서 dmg로 바로 실행할 수 있나요?

**저장소에 미리 빌드된 .dmg가 들어있지는 않지만, 터미널 없이 다운로드만으로
받는 방법도 있습니다.** `.github/workflows/build-dmg.yml`이 GitHub의 macOS
러너(Xcode·Homebrew가 이미 설치되어 있음)에서 자동으로 `.dmg`를 빌드합니다:

- **버전 태그가 푸시되면** 자동으로 빌드해서 저장소의 **Releases** 페이지에
  `.dmg`를 올립니다 — Releases 탭에서 다운로드 → 더블클릭이면 끝, 터미널
  전혀 필요 없습니다.
- 태그 없이도 **Actions 탭 → "Build macOS DMG" → Run workflow** 버튼으로
  언제든 수동 실행할 수 있습니다 (이 경우 결과물은 Release가 아니라 해당
  실행의 "Artifacts"에서 다운로드).

아래는 이 자동 빌드가 없을 때, 또는 직접 소스를 받아 Mac에서 빌드하고 싶을
때의 방법입니다 — 빌드 과정 전체를 스크립트 하나로 자동화해 뒀습니다.

### 사전 준비물 (Mac에서 한 번만, 직접 빌드할 경우)

```bash
# Xcode 커맨드라인 도구 (Xcode.app은 App Store에서 미리 설치)
xcode-select --install

# XcodeGen — project.yml로부터 .xcodeproj를 생성해 줌
brew install xcodegen

# Tesseract 본체 + 언어 데이터 (그리스어/라틴어/영어 포함 전체 팩)
brew install tesseract tesseract-lang
```

### 한 줄로 빌드하기

```bash
git clone <이 저장소 URL>
cd Classics-PDF-Assistant
./scripts/build_dmg.sh
```

성공하면 `dist/ClassicsPDFAssistant.dmg`가 생성됩니다. 더블클릭해서 마운트한
뒤, 앱을 `Applications` 폴더로 드래그하면 설치 끝입니다.

`build_dmg.sh`가 내부적으로 하는 일:
1. Python 가상환경 생성 + 백엔드 의존성 설치
2. `backend/packaging/build_backend.sh` 실행 — Tesseract 언어 데이터
   다운로드, Homebrew Tesseract 바이너리를 앱에 넣을 수 있게 정리(dylib
   경로 재작성), `pdf_backend`를 PyInstaller로 단일 실행파일 묶음으로 프리징
3. `xcodegen generate` — `project.yml`로부터 `.xcodeproj` 생성
4. `xcodebuild`로 Release 빌드 (애드혹 서명, Apple 개발자 계정 불필요)
5. `hdiutil`로 `.app`을 `.dmg`로 패키징

### 처음 실행할 때 "확인되지 않은 개발자" 경고가 뜨는 이유

이 빌드는 **애드혹(ad-hoc) 서명**만 되어 있고, Apple의 공식 **Notarization**
(공증)을 거치지 않았습니다. Notarization을 받으려면 유료 Apple Developer
Program 계정이 필요해서, 개인/로컬 빌드 용도로는 포함하지 않았습니다. 그래서
macOS Gatekeeper가 처음 실행 시 "확인되지 않은 개발자입니다" 같은 경고를
띄울 수 있습니다. 정상입니다 — 다음 중 하나로 열어주면 됩니다:

- Finder에서 앱을 **우클릭(또는 control-클릭) → 열기** → 뜨는 대화상자에서
  다시 "열기" 선택 (최초 1회만 필요)
- 또는 **시스템 설정 → 개인정보 보호 및 보안** 에서 "그래도 열기" 클릭

한 번 이렇게 열고 나면 이후에는 평소처럼 더블클릭으로 실행됩니다.

앱을 다른 사람에게 배포하려면(공식 배포판) Apple Developer Program 가입 후
Developer ID 인증서로 서명 + `xcrun notarytool`로 공증하는 과정이 추가로
필요합니다 — 이 저장소에는 포함되어 있지 않으며, 필요해지면 별도로
`build_dmg.sh`를 확장하면 됩니다.

### 빌드가 실패한다면 (단계별로 직접 해보기)

`build_dmg.sh`의 각 단계를 수동으로 실행해 어디서 막히는지 확인할 수
있습니다:

```bash
# 1) 백엔드 의존성
cd backend
python3 -m venv ../.venv && source ../.venv/bin/activate
pip install -r requirements.txt

# 2) 백엔드 프리징 (Tesseract 바이너리 번들링 포함)
./packaging/build_backend.sh

# 3) Xcode 프로젝트 생성
cd ../ClassicsPDFAssistant
xcodegen generate

# 4) Xcode에서 직접 열어 빌드/실행 (디버깅에 편리)
open ClassicsPDFAssistant.xcodeproj
```

`backend/packaging/build_backend.sh`는 Homebrew Tesseract의 dylib 의존성을
`otool -L` / `install_name_tool`로 재작성하는 등 macOS 전용 작업을 하므로,
이 부분이 가장 실패하기 쉬운 지점입니다 — 에러 메시지와 함께
`docs/ARCHITECTURE.md`의 "What's built vs. designed-only" 절을 참고하세요.

---

## 제거하기

두 가지 방법이 있고, 둘 다 내보낸 PDF 등 사용자 문서는 절대 건드리지
않습니다 (지우는 대상은 앱 자신의 설정/임시 파일/앱 번들뿐):

- **앱 안에서**: 메뉴 막대의 "ClassicsPDFAssistant" 메뉴 →
  **Uninstall Classics PDF Assistant…**. 저장된 설정(UserDefaults)과 임시
  작업 파일을 지우고, Finder에서 앱을 선택해 보여줍니다 — 앱 자체는 직접
  휴지통으로 드래그해서 마무리하면 됩니다. (실행 중인 앱이 자기 자신의
  번들을 직접 지우는 건 불안정할 수 있어 일부러 여기서 멈춥니다.)
- **dmg에 동봉된 `Uninstall.command`**: `.dmg`를 열면 앱 옆에 이 파일이
  같이 들어있습니다. 더블클릭하면 터미널이 열리고, 확인 후 앱 종료 → 설정
  삭제 → 임시 파일 삭제 → **`/Applications`의 앱 자체까지** 한 번에
  삭제합니다. 완전히 정리하고 싶을 때 이쪽을 쓰면 됩니다.

## 개발 워크플로

### 백엔드만 빠르게 테스트하기 (Mac 불필요, 리눅스에서도 가능)

앱의 핵심 로직(디스큐, 크롭, OCR, 메타데이터, 내보내기)은 Python 백엔드에
있고, Xcode 없이도 독립적으로 개발·테스트할 수 있습니다:

```bash
cd backend
python3 -m venv ../.venv && source ../.venv/bin/activate
pip install -r requirements.txt
pip install -e ".[dev]"
pytest
```

자세한 내용은 [`backend/README.md`](backend/README.md) 참고.

### Swift 앱만 반복 개발하기 (매번 전체 dmg 빌드할 필요 없음)

한 번 `xcodegen generate`로 프로젝트를 만든 뒤에는 Xcode에서 열어 평소처럼
빌드/실행하면 됩니다. 이때는 `backend/packaging/build_backend.sh`(PyInstaller
프리징)를 매번 돌릴 필요 없이, `BackendLocator`가 자동으로 로컬 Python
가상환경(`backend/.venv`)을 대신 사용하도록 폴백 처리되어 있습니다 (Xcode
스킴에 `CLASSICS_PDF_ASSISTANT_REPO_ROOT` 환경변수가 이미 설정되어 있음).
자세한 내용은 [`ClassicsPDFAssistant/README.md`](ClassicsPDFAssistant/README.md).

`scripts/build_dmg.sh`(전체 프리징 + 배포용 dmg)는 릴리스처럼 실제 패키징
결과를 확인하고 싶을 때만 실행하면 됩니다.

## 이 저장소에서 실제로 빌드/테스트된 것과 아닌 것

- **`backend/`**: 이 개발 환경(macOS/Xcode 없는 리눅스 샌드박스)에서 실제로
  구현하고 테스트했습니다. 디스큐/크롭/메타데이터/내보내기는 합성 이미지로,
  OCR은 실제 설치된 Tesseract(grc/lat/eng)로 검증했습니다.
- **`ClassicsPDFAssistant/`**: 전체 소스 트리를 작성했지만, 이 환경에는
  Xcode가 없어 컴파일/실행은 하지 못했습니다. 위 안내대로 Mac에서
  `xcodegen generate` 후 빌드하면 됩니다.
- **`scripts/build_dmg.sh`, `scripts/Uninstall.command`, `backend/packaging/*`**:
  macOS 전용 스크립트라 이 환경에서 실행/검증이 불가능했습니다 (`bash -n`으로
  문법 오류만 확인). 각 스크립트 주석에 무엇을 가정하는지 적어 두었습니다.
- **`.github/workflows/build-dmg.yml`**: GitHub의 macOS 러너에서 실행되는
  CI 워크플로라 이 세션에서 실행 결과를 직접 확인하지는 못했습니다 (이
  세션의 git 푸시 권한이 지정된 브랜치로만 제한되어 있어 태그를 직접 푸시해
  트리거해 보는 것도 불가능했습니다) — YAML 문법만 검증했습니다.

더 자세한 설계/제약 사항은 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)의
"What's built vs. designed-only in this repository" 절을 참고하세요.
