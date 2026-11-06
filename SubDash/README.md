# SubDash — AI 구독 사용량 대시보드 (macOS)

Claude, ChatGPT Codex, Lovable, Genspark, Gemini 구독을 작은 창 하나에서 봅니다.
검정 바탕 + 코발트 블루 강조, 양각 카드·음각 트랙의 뉴모피즘 UI.

## 화면

- **한눈에**: 5개 서비스 카드 (5시간·주간 사용률, 리셋까지 남은 시간, 결제 D-day, 월 합계)
- **Claude**: 5시간 세션, 주간(전체·Opus·Sonnet) 한도, 리셋 시각, 연결 상태, 일별 사용 히트맵
- **Codex**: 5시간·주간 한도, 연결 상태, 일별 사용 히트맵
- **웹 로그인**: 카드를 누르면 서비스 로그인 창 → 로그인 → 크레딧·결제일이 보이는 페이지에서 `이 페이지에서 사용량 읽기`
- **설정**: 항상 위에, 메뉴 막대 표시, 자동 새로고침, 환율
- 메뉴 막대에 `C 1%  X 23%` 처럼 Claude/Codex 5시간 사용률 표시

## 실제 값 연결

| 서비스 | 방법 | 상태 표시 |
| --- | --- | --- |
| Claude | Claude Code 로그인 토큰(키체인 `Claude Code-credentials`)으로 `api.anthropic.com/api/oauth/usage` 조회 | 성공 시 코발트 |
| Codex | `~/.codex/auth.json` 로 `chatgpt.com/backend-api/wham/usage` 조회, 실패 시 Codex 로그의 rate_limits | 로그 기준이면 흐린 청회색 |
| Lovable · Genspark | 공개 API 없음 → **앱 안 로그인 창**으로 로그인 후, 크레딧이 보이는 페이지를 15분마다 읽음 | 읽기 성공 시 코발트 |
| Gemini | 사용 한도 페이지가 없음 → 앱 안 로그인 창으로 Google One 의 플랜·결제일을 읽음 (Gemini CLI 기록 추정도 선택 가능) | 읽기 성공 시 코발트 |

실시간 값을 못 받으면 막대·아이콘 색이 **회색으로 죽고**, 실패 사유와 마지막 성공 시각이 표시됩니다.

- 처음 Claude 조회 시 macOS 가 `security` 의 키체인 접근을 물으면 **항상 허용**.
- 토큰 만료 시 터미널에서 `claude` (또는 `codex`) 를 한 번 실행하면 갱신됩니다.
- 토큰은 해당 서비스 서버로만 전송되고 앱은 따로 저장하지 않습니다. 사용 기록은 `~/Library/Application Support/SubDash/` 에만 저장.

## 설치

Actions → Build SubDash DMG → 최신 실행 → Artifacts 에서 DMG 를 받아 응용 프로그램으로 옮긴 뒤:

```bash
xattr -cr /Applications/SubDash.app
```

## 직접 빌드 (Mac)

```bash
cd SubDash
./scripts/build_dmg.sh        # build/SubDash-1.0.0.dmg
swift run                     # 개발 중 바로 실행
```
