# Tokamak Private App Channels / private-state DApp / the-great-first-channel

## 국내 중앙거래소 상장폐지 리스크 회피용 홍보·운영 체크리스트

**작성 기준일:** 2026-05-11  
**대상:** Tokamak Network, TON, Tokamak Private App Channels, private-state DApp, `the-great-first-channel`  
**용도:** 대외 홍보자료, GitHub/NPM 문서, CLI 안내문, 거래소 설명자료, 운영정책 검토용  
**주의:** 이 문서는 법률의견서가 아니며, 업비트·빗썸·코인원·DAXA·FIU·FSC의 실제 판단을 보장하지 않는다. 상장유지와 특금법/VASP 해당성에 관한 최종 판단은 외부 로펌 및 거래소 컴플라이언스 팀과 별도로 확인해야 한다.

---

## 0. 문서의 핵심 목적

이 문서의 목표는 하나다.

> **TON 자체를 “전송기록을 확인할 수 없는 가상자산”으로 보이게 만들지 않고, Tokamak Private App Channels를 “거래소가 직접 지원하는 프라이버시 입출금 네트워크”가 아니라 “투명한 L1 경계 위에서 선택적으로 이용하는 private-state application channel”로 일관되게 설명하는 것.**

국내 중앙거래소의 공개 기준은 공통적으로 다음 요소를 본다.

- 주요 지갑 정보 모니터링 가능성
- 블록 익스플로러 등 적절한 감시 수단
- 전송기록 확인 가능성
- 자금세탁·테러자금조달·법규 우회·불법도박 등에 사용될 개연성
- 발행주체·운영주체의 신뢰성
- 기술·보안·운영 안정성
- 이용자 보호 필요성

따라서 Tokamak의 대외 메시지는 다음 구조로 고정되어야 한다.

> **TON은 중앙거래소가 취급하는 투명한 L1 자산으로 남는다. Tokamak Private App Channels는 사용자가 자기수탁 지갑에서 opt-in 방식으로 이용하는 confidential application-state layer다. 거래소가 직접 다루는 TON 입출금과 L1 브리지 입출금은 투명하게 관측 가능하며, private한 것은 channel 내부 note transfer의 상대방 관계와 provenance다.**

---

## 1. 절대 원칙: “TON은 투명한 L1 자산, private-state는 opt-in DApp state”

홍보자료, GitHub README, NPM README, CLI help, 거래소 설명자료, FAQ, 보도자료에서 반드시 같은 문장을 반복해야 한다.

> **Tokamak Private App Channels는 TON 자체의 L1 전송규칙을 바꾸지 않는다. 중앙거래소가 취급하는 TON 입출금은 기존 거래소 지원 네트워크의 투명한 TON 전송으로 남는다. private-state DApp은 사용자가 자기수탁 L1 지갑으로 TON을 이동한 뒤, 별도의 application channel 안에서 선택적으로 이용하는 proof-backed confidential state layer다.**

이 문장이 흔들리면 거래소는 TON을 “프라이버시 기능이 붙은 자산”으로 볼 수 있다. 반대로 이 문장이 일관되면 방어 논리는 AZTEC의 공개 상장 전략과 가까워진다.

AZTEC의 공개 상장자료에서 확인되는 핵심은 다음과 같다.

- 거래소 입출금 네트워크는 Ethereum으로 한정되었다.
- AZTEC 토큰은 Ethereum L1의 ERC-20 표면에서 거래소가 취급했다.
- Aztec 네트워크의 private state 기능은 숨기지 않았지만, 거래소가 직접 지원하는 입출금 네트워크와 분리되었다.
- 모니터링 도구, 노드 현황, 자산 설명 자료가 함께 제공되었다.

Tokamak 쪽도 같은 방식으로 설명해야 한다.

- 거래소가 보는 TON은 기존의 투명한 L1 TON이다.
- private-state note는 거래소 지원 자산이 아니다.
- `the-great-first-channel`은 거래소 입출금 네트워크가 아니라 opt-in application channel이다.
- L1 bridge deposit과 withdraw는 온체인에서 관측 가능하다.
- 내부 note transfer의 상대방·provenance는 public observer가 기본적으로 복원하지 못한다.

---

## 2. AZTEC에서 모방해야 할 공개 상장 전략

### 2.1 CEX edge를 투명한 L1/ERC-20 표면으로 고정

AZTEC의 가장 중요한 전략은 **거래소 입출금 네트워크와 private execution network를 분리**한 것이다. 한국 거래소가 실제로 취급한 표면은 private network 내부 상태가 아니라 Ethereum 위의 투명한 토큰이었다.

Tokamak이 따라야 할 방식은 다음과 같다.

- [x] 거래소가 취급하는 것은 **TON의 기존 L1 전송**뿐이라고 설명한다.
- [x] private-state note, channel balance, note commitment, encrypted note payload를 **거래소 입출금 대상 자산**처럼 표현하지 않는다.
- [x] “TON이 private해진다”가 아니라 **“self-custody 사용자가 opt-in DApp channel에서 private-state 기능을 이용할 수 있다”**고 표현한다.
- [x] 거래소가 private-state channel을 직접 deposit network로 지원하지 않는다는 점을 명확히 한다.
- [x] private note를 “TON”이라고만 부르지 말고, **“channel-local note representation”**, **“private-state note”**, **“application-level accounting state”**라고 부른다.

### 2.2 “프라이버시 코인”이 아니라 “programmable privacy infrastructure”로 포지셔닝

Aztec은 프라이버시를 숨기지 않았다. 대신 “익명 코인”이 아니라 다음과 같이 설명했다.

- public/private state를 모두 지원하는 programmable privacy L2
- 사용자가 무엇을 public/private로 둘지 선택할 수 있는 인프라
- no backdoor 원칙
- compliant app을 만들 수 있는 customizable controls

Tokamak 홍보도 같은 방향이어야 한다.

#### 금지 프레임

- [x] “TON 익명 송금”
- [x] “거래소도 추적 불가”
- [x] “자금 출처를 숨길 수 있음”
- [x] “untraceable TON”
- [x] “mixer”
- [x] “tumbler”
- [x] “dark coin”
- [x] “현금화 추적 방지”
- [x] “규제기관·거래소 감시 회피”

#### 권장 프레임

- [x] “proof-backed confidential application state”
- [x] “L1-transparent bridge edge”
- [x] “user-controlled private note state”
- [x] “selective disclosure capable architecture”
- [x] “privacy-preserving DApp channel”
- [x] “TON custody remains anchored on L1”
- [x] “internal note transfer privacy, transparent L1 entry/exit”

### 2.3 모니터링 자료를 먼저 공개

AZTEC의 공개자료에서 중요한 점은 “모든 private history를 거래소가 볼 수 있다”가 아니라, **거래소가 봐야 할 public surface를 충분히 제공한다**는 방식이었다.

Tokamak도 홍보 전에 반드시 다음을 공개해야 한다.

- [x] Bridge contract 주소
- [x] Vault contract 주소
- [x] ChannelManager 주소
- [x] `the-great-first-channel` 생성 트랜잭션
- [x] private-state DApp 등록 정보
- [x] verifier contract 주소
- [x] proxy/admin/owner/multisig 주소
- [x] 업그레이드 권한 구조
- [x] event schema
- [x] explorer 링크
- [x] accepted transition log
- [x] nullifier/commitment/event 관측 방법
- [x] “무엇은 보이고, 무엇은 보이지 않는지” 매트릭스

이 자료가 없으면 거래소는 “적절한 감시수단이 부족하다”고 판단할 수 있다.

---

## 3. 홍보자료 필수 문구 체크리스트

아래 항목은 홈페이지, 블로그, GitHub README, NPM README, CLI help, press release, 거래소 설명자료에 모두 반영해야 한다.

### 3.1 반드시 넣어야 할 문구

- [x] **TON의 중앙거래소 입출금은 기존 거래소 지원 네트워크에서 투명하게 이루어진다.**
- [x] **Tokamak Private App Channels는 중앙거래소 입출금 네트워크가 아니다.**
- [x] **private-state notes는 거래소에 입금할 수 있는 별도 자산이 아니다.**
- [x] **사용자는 먼저 자기수탁 L1 지갑으로 TON을 보유한 뒤 opt-in 방식으로 channel을 이용한다.**
- [x] **L1 bridge deposit과 withdraw는 온체인에서 관측 가능하다.**
- [x] **channel join, L1/L2 identity registration, note-receive public key registration 등 공개 등록 이벤트는 관측 가능하다.**
- [x] **내부 note transfer의 상대방·provenance는 public contract state에서 기본적으로 복원되지 않는다.**
- [x] **Tokamak 또는 channel operator는 사용자의 spending key, wallet secret, note viewing secret을 보유하지 않는다.**
- [x] **사용자는 필요한 경우 자신이 보유한 note 또는 거래 사실을 선택적으로 증빙할 수 있다. 단, 실제 구현되어 있는 범위만 홍보한다.**
- [x] **이 시스템은 자금세탁, 테러자금조달, 제재 회피, 법규 우회, 불법도박, 범죄수익 은닉 목적으로 사용되어서는 안 된다.**

### 3.2 반드시 피해야 할 문구

- [x] “TON을 익명화한다.”
- [x] “거래소가 자금 출처를 추적할 수 없다.”
- [x] “현금화 시 출처를 숨길 수 있다.”
- [x] “CEX off-ramp privacy.”
- [x] “untraceable TON.”
- [x] “완전 익명 송금.”
- [x] “규제기관·거래소 추적 방지.”
- [x] “mixer보다 안전하다.”
- [x] “다크코인 기능.”
- [x] “상장 거래소가 인정한 프라이버시 송금.”

특히 마지막 표현은 위험하다. AZTEC 사례는 긍정적 비교 사례일 수는 있지만, “한국 거래소가 private-state 송금을 승인했다”는 의미가 아니다. AZTEC의 공개자료에서 확인되는 전략은 **Ethereum CEX edge + optional private state + public monitoring 자료**이지, 거래소가 내부 private history를 전부 수용·보증했다는 것이 아니다.

---

## 4. “전송기록 확인 가능성” 대응 매트릭스

거래소와 FIU 관점에서 가장 중요한 문서는 이 매트릭스다. 홍보자료에는 요약본을 넣고, GitHub에는 상세본을 공개해야 한다.

| 달성 여부 | 구분 | 공개/감시 가능 여부 | 거래소·감시자가 알 수 있는 것 | 알 수 없는 것 | 문서화 방식 |
|---|---|---:|---|---|---|
| [x] | CEX → 사용자 L1 지갑 TON 출금 | 가능 | 거래소 고객의 출금 주소, 금액, 시간 | 이후 사용자가 자기수탁 지갑에서 무엇을 할지 | 기존 CEX 기록 + L1 explorer |
| [x] | 사용자 L1 지갑 → Tokamak bridge deposit | 가능 | L1 주소, bridge 주소, 금액, tx hash, 시간 | 사용자의 향후 note 상대방 | Etherscan / bridge event |
| [x] | Channel join | 가능 | L1 account, L2 address pair, note-receive public key, channel name/id | 사용자의 향후 private note 상대방 | ChannelManager event |
| [x] | Deposit-channel / accounting move | 가능 | bridge vault에서 channel accounting으로 들어간 금액·상태변경 | 그 금액이 향후 어떤 note transfer로 이어지는지 | bridge/channel event |
| [x] | Note mint | 부분 가능 | commitment 생성, encrypted note-delivery event, storage update | note plaintext, owner 의미, 내부 용도 | commitment/nullifier/event explorer |
| [x] | Note transfer | 부분 가능 | transition accepted, commitment/nullifier/ciphertext event | sender-recipient 관계, note provenance | public observer + 사용자 선택증빙 |
| [x] | Redeem note to channel balance | 부분 가능 | redeem transition, nullifier usage, accounting update | 해당 note가 내부에서 누구로부터 왔는지 | channel event |
| [x] | Withdraw-channel / bridge withdraw | 가능 | L1 주소, 금액, tx hash, 시간 | 내부 note provenance | Etherscan / bridge event |
| [x] | 사용자 L1 지갑 → CEX 입금 | 가능 | CEX 입금 주소, 금액, 시간, source가 bridge 출금 주소일 수 있음 | 내부 note sender/provenance | CEX + L1 explorer |

이 표에서 가장 중요한 문장은 다음이다.

> **Tokamak은 CEX-facing TON transfer의 전송기록을 숨기지 않는다. 다만 private-state DApp 내부 note transfer의 상대방 관계와 note provenance는 public observer가 기본적으로 복원할 수 없다. 이 제한은 은폐하지 않고 명시한다.**

이 방식은 거래소 정책상 “전송기록 확인 가능성” 질문에 대한 방어 논리다. 즉 거래소가 취급하는 TON 입출금 기록은 확인 가능하고, 확인이 어려운 것은 거래소가 직접 취급하지 않는 opt-in private-state DApp 내부 history라는 점을 반복해야 한다.

---

## 5. 거래소 제출용 “Monitoring Packet” 체크리스트

홍보 전에 별도 문서 또는 repo 디렉터리로 **CEX Monitoring Packet**을 공개해야 한다. 파일명은 예를 들어 다음처럼 구성할 수 있다.

- `TPAC-CEX-Boundary-Memo.md`
- `TPAC-Contract-Addresses.json`
- `the-great-first-channel-Policy-Snapshot.json`
- `Private-State-Observability-Matrix.md`
- `Admin-Wallets-and-Upgrade-Policy.md`
- `Security-and-Incident-Response.md`
- `Selective-Disclosure-Design.md`
- `Marketing-Compliance-Guidelines.md`

### 5.1 Contract address pack

아래 정보를 빠짐없이 공개한다.

- [x] chain ID
- [x] canonical TON contract address
- [x] bridge core address
- [x] L1 token vault address
- [x] ChannelManager address
- [x] `the-great-first-channel` channel id/name
- [x] channel creation tx hash
- [x] private-state DApp id
- [x] private-state DApp registration tx hash
- [x] verifier contract addresses
- [x] Groth16 verifier / Tokamak zk-EVM verifier addresses
- [x] proxy addresses
- [x] implementation addresses
- [x] proxy admin addresses
- [x] owner/admin/multisig/timelock addresses
- [x] treasury or fee recipient addresses
- [x] channel leader/operator address
- [x] deployment block number
- [x] deployed Git commit hash
- [x] NPM package version used for deployment/proving/CLI
- [x] source verification status
- [x] ABI links
- [x] bytecode hash

### 5.2 Event and monitoring map

다음 이벤트를 문서화한다.

- [x] bridge deposit event
- [x] bridge withdraw event
- [x] channel created event
- [x] channel joined event
- [x] L1/L2 identity registration event
- [x] note-receive public key registration event
- [x] deposit-channel event
- [x] withdraw-channel event
- [x] note commitment created event
- [x] nullifier used event
- [x] encrypted note-delivery event
- [x] proof accepted event
- [x] storage root / commitment root update event
- [x] policy snapshot event
- [x] verifier or metadata update event
- [x] proxy upgrade event
- [x] emergency pause or migration event, 존재한다면

각 이벤트마다 다음을 적어야 한다.

- event name
- contract address
- indexed fields
- non-indexed fields
- explorer query 예시
- 이 event로 알 수 있는 것
- 이 event로 알 수 없는 것
- 거래소 모니터링상 의미

### 5.3 Public Channel Observer

AZTEC의 Etherscan + Aztec monitoring 자료와 비슷하게, Tokamak도 별도 explorer 또는 observer page를 제공해야 한다. 기능은 내부 note deanonymization이 아니라 **public edge visibility**다.

필수 기능:

- [ ] `the-great-first-channel` 상태 페이지
- [ ] latest accepted transition
- [ ] total L1 bridge deposits
- [ ] total L1 bridge withdrawals
- [ ] channel participants count
- [ ] channel join list
- [ ] registered L1/L2 address pair list
- [ ] note-receive public key list
- [ ] commitment event list
- [ ] nullifier event list
- [ ] encrypted payload event list
- [ ] verifier version
- [ ] channel policy hash
- [ ] DApp metadata hash
- [ ] source code / ABI link
- [ ] admin wallet status
- [ ] upgrade history
- [ ] incident notices

권장 설명문:

> **This observer does not deanonymize private note transfers. It provides exchange-grade visibility into L1 bridge edges, channel registration, accepted transitions, commitments, nullifiers, encrypted note events, verifier versions, and channel policy.**

---

## 6. Selective disclosure / viewing key 정책

이 항목은 매우 중요하다. 거래소 상장유지를 위해 **global auditor backdoor**를 넣는 방향으로 가면 안 된다. AZTEC의 공개전략도 기본적으로 “no backdoor”와 “앱이 선택적으로 compliant controls를 만들 수 있다”는 구조이지, 거래소가 모든 note history를 복원하는 구조가 아니다.

Tokamak 문서도 note-receive public key는 on-chain에 등록되지만, note-receive private key와 L2 spending key는 사용자 측에서 파생·관리되는 것으로 설명해야 한다. 즉 operator가 사용자의 note를 보는 구조라고 홍보하면 안 된다.

### 6.1 반드시 지킬 원칙

- [x] Tokamak, 회사, channel operator는 사용자의 spending key를 보유하지 않는다.
- [x] Tokamak, 회사, channel operator는 사용자의 wallet secret을 보유하지 않는다.
- [x] Tokamak, 회사, channel operator는 모든 note plaintext를 볼 수 있는 master viewing key를 보유하지 않는다.
- [x] auditor 또는 거래소에 모든 note copy가 자동 전달되는 구조를 상장유지 장치로 홍보하지 않는다.
- [x] selective disclosure는 **사용자 통제형**이어야 한다.
- [x] viewing key 공유는 spending key 공유와 명확히 분리해야 한다.
- [x] 사용자가 선택적으로 제출할 수 있는 증빙자료의 범위를 문서화한다.
- [x] 구현되지 않은 disclosure 기능을 홍보하지 않는다.

### 6.2 사용자 선택공개 기능으로 준비할 항목

- [x] 사용자가 보유한 note를 로컬에서 복호화한다.
- [x] 사용자가 특정 note의 commitment, creation tx, amount, channel id를 확인한다.
- [x] 사용자가 특정 note가 자신에게 전달되었음을 증명할 수 있는 자료를 export한다.
- [x] 사용자가 특정 redeem 또는 withdraw와 자신의 note 사용을 연결해 설명할 수 있는 자료를 export한다.
- [x] 이 export는 spending key를 포함하지 않는다.
- [x] 이 export는 전체 wallet history를 강제로 공개하지 않는다.

- [x] 특정 기간의 note receipt proof
- [x] 특정 counterparty와의 거래만 선택 공개
- [x] 특정 bridge deposit과 note mint 간 사용자 주도 linkage proof
- [x] 특정 redeem과 note ownership 간 linkage proof
- [x] 거래소 요청 대응용 user consent disclosure package

CLI 문서에 넣을 권장 문구:

> **Tokamak cannot disclose a user’s private note history on behalf of the user because Tokamak does not hold the user’s viewing or spending secrets. A user may voluntarily generate selected evidence from their local wallet state.**

### 6.3 auditor note-copy 기능에 대한 정책

Aztec에는 contract-level로 note를 제3자에게 전달할 수 있는 프리미티브가 존재하지만, 이것은 상장 조건으로 확인된 기능이 아니라 특정 앱이 선택적으로 사용할 수 있는 compliance primitive에 가깝다. Aztec은 동시에 no backdoor와 customizable compliance controls를 강조한다.

Tokamak의 권장 정책은 다음이다.

- [x] `the-great-first-channel` 기본 정책에 global auditor note-copy를 넣지 않는다.
- [x] 모든 note를 회사 또는 거래소가 볼 수 있게 만드는 master auditor를 두지 않는다.
- [x] auditor 기능을 넣는다면 별도 channel 또는 별도 DApp policy로 분리한다.
- [x] auditor 기능이 있는 channel은 명확히 “audited channel”이라고 표시한다.
- [x] unaudited/private channel과 audited channel을 혼동시키지 않는다.
- [x] 거래소에는 “global backdoor는 없지만, 사용자 선택공개와 public edge monitoring을 제공한다”고 설명한다.

---

## 7. `the-great-first-channel` 전용 운영 체크리스트

### 7.1 Channel public profile

다음 정보를 하나의 페이지에 공개한다.

- [x] Channel name: `the-great-first-channel`
- [x] Channel id
- [x] creation tx hash
- [x] creator / channel leader address
- [x] DApp id
- [x] DApp label: private-state DApp
- [x] ChannelManager address
- [x] linked bridge address
- [x] linked vault address
- [x] canonical TON address
- [x] accepted function root
- [x] storage layout hash
- [x] verifier snapshot
- [x] metadata digest
- [x] join policy
- [x] toll/refund policy
- [x] upgradeability policy
- [ ] emergency policy
- [x] latest accepted transition
- [x] latest policy version
- [x] source commit and package versions

### 7.2 Channel operator 설명

문서에서 “operator”라는 단어를 사용할 때는 반드시 제한적으로 설명해야 한다. 운영자가 proving, relaying, service operation을 조율하는 것처럼 보이는 표현은 거래소 입장에서 운영자 개입 가능성으로 읽힐 수 있으므로, 실제 운영 모델을 명확히 적어야 한다.

권장 문구:

> **The channel operator opens and maintains public channel metadata and policy. The operator does not custody user TON, does not hold user note secrets, does not intermediate user transfers, and does not have a protocol backdoor to reconstruct private note provenance.**

반드시 금지할 운영 방식:

- [x] 사용자의 private key 또는 wallet secret을 서버가 수집
- [x] 사용자의 note plaintext를 서버가 저장
- [x] 사용자의 transfer proof를 운영자 서버에서 독점 생성
- [x] 운영자 서버 없이는 사용자가 redeem/withdraw 불가능
- [x] 운영자가 사용자 쿼리를 받아 대리 실행
- [x] 운영자가 사용자 간 송금을 중개
- [x] 운영자가 private history를 임의 열람

이 중 하나라도 실제로 존재한다면 홍보 전에 별도 VASP/AML 법률검토가 필요하다.

---

## 8. GitHub / NPM / CLI 문서 체크리스트

Tokamak 공개 repo와 NPM 패키지는 “비수탁·사용자 로컬 실행” 논리를 뒷받침해야 한다. 문서가 불명확하면 거래소가 운영자 중개로 오해할 수 있다.

### 8.1 GitHub README에 추가해야 할 섹션

- [ ] `CEX Boundary and Monitoring`
- [ ] `What is public and what is private`
- [ ] `Not a mixer / not a CEX deposit network`
- [ ] `User-controlled selective disclosure`
- [ ] `No operator-held viewing key`
- [ ] `No custody by Tokamak`
- [ ] `Known limitations`
- [ ] `AML / sanctions / illegal-use prohibition`
- [ ] `Contract addresses and monitoring`
- [ ] `the-great-first-channel public profile`
- [ ] `Upgrade and incident response policy`

### 8.2 NPM README에 추가해야 할 문구

CLI 설치 페이지와 사용 예시에 다음 경고를 넣는다.

- [x] **Do not use a centralized exchange deposit address as a private-state wallet address. Private-state notes are not supported exchange assets. Always withdraw TON to a self-custody L1 wallet before using a channel.**
- [x] **Bridge deposits and withdrawals are public L1 events. Internal note transfers are private by design and are not automatically reconstructible by Tokamak, exchanges, or public observers.**
- [x] **This CLI does not send your spending key, wallet secret, or private note plaintext to Tokamak.**

### 8.3 CLI 실행 중 표시해야 할 경고

특히 `join`, `deposit-channel`, `mint`, `transfer`, `redeem`, `withdraw-channel` 전에 다음 정보를 표시해야 한다.

- [x] 이 action이 L1에서 public event를 발생시키는지
- [x] 이 action이 private note state를 변경하는지
- [x] 어떤 주소와 금액이 public인지
- [x] 어떤 정보가 public이 아닌지
- [x] note provenance가 public observer에게 복원되지 않는다는 점
- [x] 불법 목적 사용 금지
- [x] CEX deposit address 사용 금지
- [x] wallet secret 분실 시 recovery 한계
- [x] 사용자가 policy snapshot을 확인했다는 체크

---

## 9. 보안·거버넌스 체크리스트

거래소 입장에서는 프라이버시 기능 자체만 보는 것이 아니라, 운영주체가 신뢰 가능한지, 주요 지갑을 모니터링할 수 있는지, 업그레이드와 사고 대응이 투명한지도 본다.

### 9.1 Admin wallet / upgrade policy

- [x] UUPS/proxy owner 주소 공개
- [x] multisig 사용 여부 공개
- [x] timelock 사용 여부 공개
- [ ] owner 변경 history 공개
- [x] implementation upgrade history 공개
- [ ] emergency pause 권한 공개
- [x] verifier 교체 권한 공개
- [x] metadata update 권한 공개
- [x] channel policy는 silent mutation 불가 원칙 공개
- [x] 기존 channel 정책 변경이 필요하면 새 channel 생성 원칙 공개

Tokamak의 security model에서 bridge owner의 upgrade 권한과 privileged owner authority가 신뢰가정으로 인정되는 경우, 이 부분을 숨기면 안 된다. 오히려 거래소용 모니터링 패킷에 정면으로 넣어야 한다.

### 9.2 Audit / security disclosure

- [ ] 외부감사 완료 여부 공개
- [ ] 미감사라면 “unaudited / experimental” 표시
- [x] known limitations 공개
- [x] verifier soundness assumption 공개
- [x] metadata correctness assumption 공개
- [x] exact-transfer canonical token assumption 공개
- [x] L1 custody / L2 accounting separation 공개
- [ ] incident contact 공개
- [ ] vulnerability disclosure process 공개
- [ ] emergency migration process 공개

---

## 10. 거래소 커뮤니케이션 체크리스트

홍보 전에 업비트·빗썸·코인원에 보낼 수 있는 설명자료를 준비해야 한다. 핵심은 “내부 private note provenance를 거래소가 자동 복원할 수 있게 만들었다”가 아니다.

핵심은 다음이다.

> **거래소가 취급하는 TON 표면은 투명하고, private-state는 opt-in DApp 내부 상태이며, public edge와 major wallets와 contract events는 모니터링 가능하다.**

### 10.1 거래소 설명자료 구성

#### 1. Executive summary

- TON의 L1 전송규칙은 변경되지 않음
- CEX deposit/withdraw network는 기존 TON 지원 네트워크
- Tokamak Private App Channels는 CEX deposit network가 아님
- private-state DApp은 self-custody 사용자의 opt-in DApp

#### 2. AZTEC comparison

- 유사점: L1/Ethereum edge는 투명, 내부 private state는 선택형
- 유사점: public/private state를 구분하여 설명
- 유사점: monitoring tools와 explorer 제공
- 차이점: Tokamak은 이미 상장된 TON과 직접 연결되어 있으므로 더 엄격한 disclosure 제공
- 차이점: `the-great-first-channel`은 channel-specific DApp이며, private notes는 별도 상장자산이 아님

#### 3. CEX boundary

- CEX가 볼 수 있는 TON 입출금
- bridge deposit/withdraw 관측 방법
- 사용자가 CEX에서 현금화할 때 L1 bridge 출금 provenance는 보일 수 있음
- 내부 note sender/provenance는 기본적으로 public observer가 복원하지 못함

#### 4. Monitoring packet

- contract address table
- admin wallet table
- event map
- explorer links
- upgrade history
- incident response

#### 5. Selective disclosure

- Tokamak은 사용자 keys를 보유하지 않음
- 사용자가 선택적으로 note evidence를 제출할 수 있음
- 구현된 기능과 구현 예정 기능 구분

#### 6. Illegal-use policy

- AML/TF/제재회피/법규우회/불법도박 목적 사용 금지
- 관련 주소 또는 활동 발견 시 대응 정책
- 수사기관·거래소 요청 시 제공 가능한 public data 범위

#### 7. Legal memo

- 비수탁 구조
- 운영자 역할
- 사용자 직접 L1 interaction
- VASP 해당성 검토
- Travel Rule 경계

한국 travel rule 및 FIU 정책 환경을 고려할 때, 거래소 설명자료는 “travel rule을 우회한다”가 아니라 다음 구조여야 한다.

> **VASP 간 CEX transfer의 정보제공 체계를 건드리지 않고, self-custody 이후의 opt-in DApp state를 제공한다.**

---

## 11. 홍보 문구 샘플

### 11.1 권장 보도자료 문구: English

> Tokamak Private App Channels is an Ethereum-settled, proof-backed application channel framework. TON custody and settlement remain anchored on L1, while users may opt into private-state DApps that keep internal note ownership and note transfer semantics confidential from public contract state.

> the-great-first-channel is a public mainnet channel for the private-state DApp. Its L1 bridge deposits, withdrawals, channel registration, policy snapshot, verifier information, commitments, nullifiers, and encrypted note-delivery events are publicly observable. Internal note transfer counterparties are private by design and are not automatically reconstructed by Tokamak or public observers.

> Tokamak does not hold user spending keys, wallet secrets, or note viewing secrets. Users interact with the bridge and channel from self-custody wallets and may selectively disclose their own note-related evidence where technically supported.

> Tokamak Private App Channels are not a centralized exchange deposit network and private-state notes are not exchange-supported assets. TON deposits and withdrawals on centralized exchanges remain standard transparent TON transfers on the exchange-supported network.

### 11.2 권장 보도자료 문구: Korean

> Tokamak Private App Channels는 L1에서 정산되는 proof-backed application channel 프레임워크입니다. TON의 중앙거래소 입출금과 L1 브리지 입출금은 투명하게 관측 가능하며, private-state DApp 내부의 note transfer 의미와 상대방 관계만 public contract state에서 기본적으로 노출되지 않습니다.

> `the-great-first-channel`은 private-state DApp을 위한 공개 메인넷 channel입니다. channel 생성, 사용자 join, bridge deposit/withdraw, verifier, policy snapshot, commitment, nullifier, encrypted note-delivery event는 공개적으로 모니터링할 수 있습니다. 다만 내부 note provenance는 사용자의 선택공개 없이는 기본적으로 복원되지 않습니다.

> Tokamak은 사용자의 spending key, wallet secret, note viewing secret을 보유하지 않으며, 사용자 간 송금을 중개하거나 사용자 자산을 수탁하지 않습니다.

### 11.3 금지 문구

- [ ] “TON을 완전히 익명화합니다.”
- [ ] “거래소 현금화 시 출처를 숨길 수 있습니다.”
- [ ] “업비트·빗썸·코인원이 추적할 수 없습니다.”
- [ ] “규제기관의 감시를 피할 수 있습니다.”
- [ ] “mixer처럼 사용할 수 있습니다.”
- [ ] “프라이버시 코인으로 진화한 TON.”
- [ ] “자금 출처를 세탁할 수 있습니다.”
- [ ] “CEX off-ramp privacy.”

---

## 12. 기능 구현·운영 측면의 P0 체크리스트

아래 항목은 홍보 전에 완료해야 하는 **P0 blocker**다.

### 12.1 공개 모니터링

- [x] 모든 mainnet contract source가 Etherscan에 verified
- [x] contract address table 공개
- [x] `the-great-first-channel` public profile 공개
- [x] public observer 또는 explorer 공개
- [x] bridge deposit/withdraw event query 방법 공개
- [x] channel join / L1-L2 pair monitoring 방법 공개
- [x] commitment/nullifier/encrypted event monitoring 방법 공개
- [x] admin wallet / proxy / implementation / upgrade history 공개
- [ ] emergency notice page 공개

### 12.2 문서 정합성

- [x] GitHub README와 NPM README에서 같은 용어 사용
- [x] “TON 자체가 private asset이 된다”는 표현 제거
- [x] “untraceable” 표현 제거
- [x] “anonymous cash-out” 표현 제거
- [x] “mixer” 표현 제거
- [x] `private-state note ≠ exchange-supported TON` 명시
- [x] `CEX edge remains transparent` 명시
- [x] 내부 note provenance 비가시성을 숨기지 않고 정확히 명시

### 12.3 사용자 보호

- [x] CLI에서 CEX deposit address 사용 금지 경고
- [x] CLI에서 self-custody wallet 사용 안내
- [x] CLI에서 bridge deposit/withdraw public visibility 표시
- [x] CLI에서 note transfer privacy scope 표시
- [x] wallet secret / spending key / viewing key 보관 경고
- [x] lost secret recovery 한계 표시
- [x] illegal-use prohibition 표시
- [x] channel policy review confirmation

### 12.4 운영자 리스크

- [x] Tokamak이 사용자 keys를 보유하지 않음 명시
- [x] Tokamak이 사용자 note plaintext를 보유하지 않음 명시
- [x] Tokamak이 사용자 간 transfer를 중개하지 않음 명시
- [x] Tokamak이 private provenance를 임의 복원할 수 없음 명시
- [x] 운영 서버가 없어도 사용자가 L1과 직접 interaction 가능함 명시
- [x] 실제로 relayer/prover/indexer 서비스를 운영한다면 그 범위와 로그 보관 정책 공개
- [x] 운영자 수수료가 있다면 수취 주소와 과금 근거 공개
- [x] channel leader/operator 권한 공개

### 12.5 법률·거래소 대응

- [ ] 외부 로펌의 특금법/VASP 검토 메모 확보
- [ ] 거래소별 설명자료 준비
- [ ] DAXA 모범사례 기준 대응표 준비
- [ ] Travel Rule 영향 검토
- [ ] 불법사용 대응정책 준비
- [x] 수사기관·거래소 요청 시 제공 가능한 public data 범위 정의
- [x] 사용자 선택공개 요청 절차 정의

---

## 13. P1 권장 체크리스트

P0는 아니지만, 상장유지 리스크를 크게 낮추는 항목이다.

- [ ] public observer API 제공
- [ ] daily monitoring report 자동 생성
- [ ] 주요 contract event RSS/Telegram/Slack alert
- [ ] admin wallet movement alert
- [ ] verifier or implementation change alert
- [ ] large bridge deposit/withdraw alert
- [ ] suspicious L1 address interaction policy
- [ ] sanctions-screening 대상은 최소한 L1 bridge edge에서 검토하는 정책 수립
- [x] optional user disclosure export command
- [x] note evidence export format 표준화
- [ ] third-party security audit
- [ ] bug bounty
- [ ] reproducible build documentation
- [ ] NPM package integrity documentation
- [ ] release signing
- [x] deployment artifact archive
- [ ] Korean whitepaper summary
- [ ] Korean FAQ for exchanges and users

---

## 14. “무엇을 거래소에 솔직히 말해야 하는가”

거래소가 가장 우려할 질문은 이것이다.

> “사용자가 bridge에서 TON을 출금해 다시 거래소에 입금했을 때, 그 TON이 L2 내부에서 누구에게서 온 것인지 알 수 있는가?”

여기에 대한 답은 회피하지 말아야 한다.

권장 답변:

> **기본 public data만으로는 내부 private-state note provenance를 복원할 수 없습니다. 거래소와 public observer는 사용자의 L1 bridge entry/exit, channel join, public commitments, nullifiers, encrypted note-delivery events, accepted transitions를 볼 수 있습니다. 그러나 내부 note sender-recipient relationship과 provenance chain은 사용자의 선택공개 없이는 기본적으로 복원되지 않습니다. 이 설계는 CEX-facing TON transfer를 숨기는 것이 아니라, self-custody 이후 opt-in DApp 내부 note state의 privacy를 제공하는 것입니다.**

이 답변은 리스크를 숨기지 않기 때문에 오히려 낫다. “모든 것이 추적 가능하다”고 과장하는 것보다, **무엇이 보이고 무엇이 보이지 않는지 정확히 분리**하는 것이 상장유지 관점에서 더 안전하다.

---

## 15. AZTEC 비교 문구: 사용 가능 버전과 금지 버전

### 15.1 사용 가능한 비교

> Tokamak Private App Channels can be compared to privacy-preserving L2 architectures such as Aztec in the limited sense that both separate a transparent L1 exchange boundary from optional private application state. Like Aztec’s public materials, Tokamak distinguishes between public settlement/monitoring surfaces and private execution or note state.

이 비교는 가능하다. 핵심은 **제한된 의미에서의 구조적 비교**라는 점이다.

### 15.2 금지해야 할 비교

> “AZTEC도 상장됐으므로 Tokamak private-state도 상장폐지 리스크가 없다.”

이 문장은 위험하다. AZTEC은 별도 토큰·별도 네트워크이고, 한국 거래소는 입출금 표면을 Ethereum으로 한정했다. Tokamak은 이미 상장된 TON의 issuer/operator-linked utility로 읽힐 수 있으므로, AZTEC보다 더 강한 설명자료와 모니터링 자료가 필요하다.

### 15.3 정확한 비교 문구

> **Aztec is a positive precedent for the principle that privacy-preserving application infrastructure is not automatically incompatible with Korean centralized exchange support, provided that the exchange-supported token transfer surface remains transparent and adequate public monitoring materials are available. Tokamak applies the same boundary principle to TON: CEX-facing TON transfers and L1 bridge edges are transparent, while opt-in private-state note transfers remain confidential inside the application channel.**

---

## 16. 상장폐지 리스크를 키우는 운영 실수

아래는 피해야 할 red flag다.

- [ ] 홍보자료 첫 문장에 “익명 송금”을 넣는 것
- [ ] “거래소 현금화 출처 추적 방지”를 장점으로 말하는 것
- [ ] CEX 출금 → bridge → note transfer → CEX 입금 튜토리얼을 제공하는 것
- [x] private notes를 “TON notes”라고만 불러 TON 자체와 혼동시키는 것
- [x] CEX deposit address를 CLI 사용 예시에 넣는 것
- [x] contract addresses와 admin wallets를 공개하지 않는 것
- [ ] source code verification 없이 홍보하는 것
- [x] upgrade 권한을 숨기는 것
- [x] channel operator가 무엇을 할 수 있는지 설명하지 않는 것
- [x] 사용자 viewing key 또는 note plaintext를 서버가 보관하는데 이를 숨기는 것
- [ ] “AZTEC이 상장됐으니 문제없다”고 단정하는 것
- [x] 내부 note provenance를 복원할 수 없다는 사실을 감추는 것
- [ ] 구현되지 않은 selective disclosure 기능을 이미 있는 것처럼 홍보하는 것
- [ ] auditor backdoor를 넣고도 “완전 프라이버시”라고 홍보하는 것
- [ ] auditor backdoor가 없는데 “거래소 요청 시 모든 내부 흐름 제공 가능”이라고 홍보하는 것

---

## 17. 최종 GO / NO-GO 기준

홍보 전 내부 승인에서 아래 중 하나라도 “NO”이면 외부 홍보를 멈춰야 한다.

| 항목 | GO 기준 |
|---|---|
| CEX boundary | TON의 거래소 입출금은 기존 투명 L1 네트워크로 남는다고 모든 문서가 일관되게 설명 |
| Private-state 표현 | “TON 익명화”가 아니라 “opt-in DApp internal note privacy”로 설명 |
| Contract monitoring | 모든 주요 contract, verifier, vault, manager, channel 주소 공개 |
| the-great-first-channel | channel id, policy snapshot, creation tx, operator 권한 공개 |
| Explorer | bridge deposit/withdraw, channel join, commitments, nullifiers, encrypted events 모니터링 가능 |
| Admin wallet | owner/proxy/admin/multisig/timelock/upgrade history 공개 |
| Selective disclosure | 사용자 통제형으로만 설명하고, operator-held master viewing key 없음 |
| CLI warning | CEX deposit address 사용 금지, L1 visibility, note privacy scope 경고 |
| Illegal-use policy | AML/TF/제재회피/법규우회/불법도박 금지 명시 |
| Legal memo | 특금법/VASP/Travel Rule 영향에 대한 외부 검토 확보 |
| Exchange memo | 업비트·빗썸·코인원 제출용 monitoring packet 준비 |
| Marketing review | “anonymous/untraceable/mixer/cash-out privacy” 표현 0건 |

---

## 18. 가장 중요한 최종 메시지

Tokamak이 외부에 내야 할 메시지는 다음 하나로 수렴해야 한다.

### English

> **Tokamak Private App Channels does not make TON a dark coin. TON remains a transparent exchange-supported L1 asset. Private-state DApps provide opt-in confidential application state after a user moves TON into self-custody and interacts with a public L1 bridge. The bridge entry and exit, channel registration, policy, verifier, commitments, nullifiers, and encrypted events are publicly monitorable. Internal note provenance is private by design and can be disclosed only by the user.**

### Korean

> **Tokamak Private App Channels는 TON을 다크코인으로 만드는 기능이 아닙니다. TON은 중앙거래소가 지원하는 투명한 L1 자산으로 남습니다. private-state DApp은 사용자가 자기수탁 지갑으로 TON을 이동한 뒤 공개 L1 브리지를 통해 선택적으로 이용하는 confidential application state입니다. 브리지 입출금, channel 등록, policy, verifier, commitment, nullifier, encrypted event는 공개적으로 모니터링할 수 있습니다. 내부 note provenance는 설계상 private하며 사용자만 선택적으로 공개할 수 있습니다.**

---

## 19. 참고 링크

아래 링크들은 이 문서 작성 시 비교·검토 대상으로 사용한 공개자료다. 실제 제출문서에서는 각 링크의 최신 상태와 날짜를 다시 확인해야 한다.

- Upbit 거래지원 종료 정책: <https://static.upbit.com/guide/market_policy_close.pdf>
- Bithumb AZTEC 거래지원 공지: <https://feed.bithumb.com/notice/1652023>
- Bithumb AZTEC 자산설명서: <https://feed-content.bithumb.com/cms/3224fc67-35a4-4bce-985f-f41f4e7c4b0c.pdf>
- Aztec 공식 사이트: <https://aztec.network/>
- Aztec token page: <https://aztec.network/aztec-token>
- Aztec private world computer article: <https://aztec.network/blog/aztec-the-private-world-computer>
- Aztec policy principles: <https://aztec.network/policy-principles>
- Tokamak zk-EVM contracts repo: <https://github.com/tokamak-network/Tokamak-zk-EVM-contracts>
- Tokamak Private State security model: <https://github.com/tokamak-network/Tokamak-zk-EVM-contracts/blob/main/packages/apps/private-state/docs/security-model.md>
- Tokamak Private State workflow: <https://github.com/tokamak-network/Tokamak-zk-EVM-contracts/blob/main/packages/apps/private-state/docs/workflow.md>
- Tokamak private-state README: <https://github.com/tokamak-network/Tokamak-zk-EVM-contracts/blob/main/packages/apps/private-state/README.md>
- Tokamak Private App Channels whitepaper: <https://github.com/tokamak-network/Tokamak-zk-EVM-contracts/blob/main/bridge/docs/whitepaper.md>
- private-state CLI NPM: <https://www.npmjs.com/package/@tokamak-private-dapps/private-state-cli>
- Tokamak zk-EVM CLI NPM: <https://www.npmjs.com/package/@tokamak-zk-evm/cli>
- 특금법 시행령 링크: <https://www.law.go.kr/lumLsLinkPop.do?chrClsCd=010202&lspttninfSeq=82843>
