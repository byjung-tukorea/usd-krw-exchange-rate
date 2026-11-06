# SubDash — AI 구독 대시보드 (macOS)

Claude Code Max, ChatGPT Plus(Codex), Lovable, Genspark, Gemini 등 AI 구독의
**토큰/한도 사용량, 리셋까지 남은 시간, 다음 결제일(D-day), 월 합계**를 작은 창 하나에서 보는 개인용 맥 앱입니다.

- 360pt 폭의 작은 창, 무채색 뉴모피즘(양각 카드 + 음각 패널/트랙), 라이트·다크 자동 대응
- 토글: 구독별 켜기/끄기, 항상 위에, 메뉴 막대 아이콘, 자동 동기화, 환율 자동 갱신, 꺼진 항목 표시
- 세그먼트 전환: **사용량 ↔ 남은 양**
- 메뉴 막대 패널에서 한눈에 요약
- **구글 SSO 계정 구분**: 구독마다 `학교` / `개인` 지메일 계정을 지정하고, 상단 `전체 · 학교 · 개인` 필터로 계정별 합계·목록 보기
  (설정에서 두 계정의 이메일을 적어 두면 카드에 마우스를 올렸을 때 표시)
- 데이터는 `~/Library/Application Support/SubDash/subscriptions.json` 에만 저장 (외부 전송 없음, 환율 조회만 open.er-api.com)

## 사용량 집계 방식

| 서비스 | 방식 |
| --- | --- |
| Claude Code (Max) | `~/.claude/projects/**/*.jsonl` 로그를 읽어 **현재 5시간 블록**의 토큰(입력+출력+캐시 생성)과 리셋 시각 자동 계산 |
| ChatGPT Codex (Plus) | `~/.codex/sessions/**/*.jsonl` 의 `rate_limits` 를 읽어 5시간 한도 % 와 주간 % 자동 표시 |
| Lovable · Genspark · Gemini 등 | 공개 사용량 API가 없어 **직접 입력** (카드 우클릭 → +1/+10/초기화, 리셋 주기가 지나면 자동 0) |

Claude/ChatGPT 구독의 정확한 한도는 공개되지 않으므로, 카드의 `한도` 값은 체감에 맞게 조정하세요.

## 조작

- 카드 **더블클릭** → 편집, **우클릭** → 빠른 메뉴 (로그인 계정 바로 변경 포함)
- 상단 📌 항상 위에 · ＋ 추가 · ⚙︎ 설정
- `⌘R` 지금 동기화

## DMG 받기

GitHub Actions(`.github/workflows/macos-dmg.yml`)가 푸시마다 Universal DMG 를 빌드합니다.

1. 저장소 **Actions → Build SubDash DMG → 최신 실행 → Artifacts** 에서 `SubDash-x.y.z` 다운로드
2. `v1.0.0` 같은 태그를 푸시하면 **Releases** 에 DMG 가 첨부됩니다.

개인용 ad-hoc 서명이라 처음 실행 시 Gatekeeper 경고가 뜹니다.
앱을 `응용 프로그램`으로 옮긴 뒤 **우클릭 → 열기**, 또는 터미널에서:

```bash
xattr -cr /Applications/SubDash.app
```

## 직접 빌드 (Mac)

```bash
cd SubDash
./scripts/build_dmg.sh          # build/SubDash-1.0.0.dmg
UNIVERSAL=0 ./scripts/build_dmg.sh   # 현재 아키텍처만 (더 빠름)
swift run                       # 개발 중 바로 실행
```

요구 사항: macOS 13 이상, Xcode 15+ 또는 Command Line Tools.
