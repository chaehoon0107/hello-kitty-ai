# 나만의 데스크톱 펫

**펫 실행** 바로가기를 더블클릭하면 시작하고, **펫 종료** 바로가기로 종료합니다.

키티를 **우클릭**하면 정면을 보며 멈추고, 머리 위에 질문창이 열립니다. `무엇이 궁금하신가요` 입력창에 질문을 쓴 뒤 오른쪽 보내기 버튼이나 Enter를 누릅니다. Shift + Enter는 줄바꿈입니다. PNG/JPG/WEBP 이미지를 질문창으로 끌어 놓거나 + 버튼으로 첨부할 수 있습니다. 파일을 끌어오는 동안 질문창이 둥근 하늘색 첨부 영역으로 바뀌고, 놓으면 이미지 미리보기와 질문 입력칸이 표시됩니다.

실제 모델이 답하는 동안 네 개의 점이 움직이고 키티는 손을 턱 근처에 올린 고민 모션을 반복합니다. 답변이 완성되면 ❗ 표시 뒤 머리 위 말풍선에 요약이 차례로 나타납니다. 말풍선 오른쪽 펼치기 버튼은 별도 Kitty AI 창을 엽니다. 왼쪽에는 최근 대화, 오른쪽에는 질문·이미지·전체 답변이 표시됩니다. 이전 대화를 선택해 추가 질문을 보내면 그 대화의 문맥을 이어갑니다. ×로 말풍선을 닫으면 걷기를 재개합니다. 입력창이 열려 있을 때 Esc는 입력창을 닫습니다.

앱의 모든 UI 글꼴은 사용자가 제공한 `assets/fonts/Griun_Yeeun-Rg.ttf`입니다.

## 로컬 AI

[공식 Qwen3.5-2B](https://huggingface.co/Qwen/Qwen3.5-2B)를 내려받아 이 PC에서 실행합니다. API 키 없이 질문과 이미지를 로컬 모델에 전달합니다. AI 환경과 모델은 `ai/.venv`, `ai/models/Qwen3.5-2B`에 있습니다. 이 PC의 CPU에 맞게 Linear 계층을 INT8로 준비하고 나머지 계층은 FP32로 처리합니다. [PyTorch 동적 양자화 API](https://docs.pytorch.org/docs/main/generated/torch.ao.quantization.quantize_dynamic.html).

`start_ai.ps1`이 로컬 서버를 시작합니다. 실행 바로가기와 Godot 실행 시 자동으로 연결하며, 종료 바로가기는 서버도 함께 종료합니다. 서버는 `127.0.0.1:18935`에서만 연결을 받고 실행마다 발급한 토큰을 확인합니다. 첫 실행 시 모델을 읽고 준비하는 시간이 필요합니다. 준비 중에는 보내기를 비활성화합니다. 이 PC에서 짧은 텍스트 질문은 13~19초, 작은 이미지 질문은 약 22초로 확인했습니다. 질문 길이, 답변 길이, PC 부하에 따라 달라집니다.

제공한 구조 문서에서는 UI와 추론을 분리하는 로컬 서버, 토크나이저의 대화 템플릿, 역할별 메시지, 답변 분량을 남겨 두는 문맥 제한, 이전 대화 요약, 점진적 답변 전달, 기록 저장과 실행·종료 관리만 사용했습니다. 모델 가중치는 변경하지 않고 실행 시 양자화하며, 대화 기록은 별도의 SQLite DB에 저장합니다.

`ai/server.py`가 모델과 대화 처리를 담당하고, `ai_client.gd`는 비동기 HTTP 연결, `assistant.gd`는 펫 위 질문창과 답변 상태, `ui/chat_window.gd`는 확장 채팅창을 담당합니다. 기록은 `ai/data/conversations.sqlite3`, 첨부 이미지는 `ai/data/attachments`에 저장되어 재실행 후에도 유지됩니다. 모델에는 최근 대화와 앞선 답변 요약을 전달하며 총 4096 토큰 중 512 토큰을 새 답변에 남깁니다. 원문 기록은 문맥 제한과 관계없이 DB에 보관합니다.

현재 화면에는 팔과 다리를 리깅한 키티가 걸어다닙니다. 원래 색·텍스처와 얼굴 경계선 보정을 유지하며, 조명 명암·카툰 셰이더·외곽선을 적용하지 않습니다. 팔은 어깨에서 자연스럽게 흔들리고, 양발이 번갈아 들립니다.

- 기본 모니터의 작업표시줄 윗면에 배치한 보이지 않는 바닥을 따라 걷습니다.
- 펫을 왼쪽 마우스로 누른 채 끌어 옮길 수 있습니다.
- 위에서 놓으면 중력으로 떨어지며 Godot의 CharacterBody2D 바닥 충돌로 착지합니다.
- 마우스를 움직이다 놓으면 이동 속도가 반영됩니다.
- 화면 양 끝에 도착하면 돌아서 걷습니다.

## Godot에서 수정

`project.godot`을 Godot 4.7.2로 열면 됩니다. 바탕화면 동작 확인은 **펫 실행** 바로가기를 사용하세요.

현재 사용하는 모델은 `assets/pet_blender_rigged.glb`입니다. 16개 관절과 Idle/Walk/Think/Notice 애니메이션이 있습니다. 분리 모델의 색·UV·16개 재질을 유지하고, 어깨와 발목의 연결 정점을 하나의 메시로 붙였습니다. 공유된 정점은 같은 가중치로 움직여 연결부가 벌어지지 않습니다. 흰 팔과 신발은 형태를 유지하며, 소매와 바지 연결부만 부드럽게 따라 움직입니다. Godot에서는 원래 색과 텍스처만 표시하는 무조명 재질을 사용합니다.

보정 전 모델은 `assets/pet_original_parts.glb`에 보관되어 있습니다. `tools/repair_surface.py`가 텍스처 경계 보정을 생성하며, `previews/smooth_model.png`는 실제 Godot 표시 결과입니다.

`tools/pet_rigged_walk.blend`에서 관절과 키프레임을 수정할 수 있습니다. `Part.*` 정점 그룹으로 원래 분리 요소를 선택할 수 있습니다. `tools/blender_parts_walk.py`가 리깅을 생성하고, 전체 걷기 프레임의 발바닥 높이와 삼각형 붕괴·바닥 관통을 검사합니다. `tools/validate_blender_rig.py`는 내보낸 모델의 공유 정점 가중치와 애니메이션 반복 연결을 검사합니다.

`hidden_taskbar_plane.tscn`에는 y=0 높이의 PlaneMesh와 StaticBody3D 충돌판이 있으며 렌더링에서는 보이지 않습니다. 실제 바탕화면 이동은 같은 발바닥 높이에 대응하는 하나의 WorldBoundaryShape2D 바닥에서 처리합니다. 바닥 스냅, 반동 없는 착지, 일정한 몸통 높이와 물리 보간으로 보행 중 높이 떨림을 줄입니다. [CharacterBody2D 참고](https://docs.godotengine.org/en/stable/classes/class_characterbody2d.html).

`main.gd`는 투명 창, 3D 렌더링, 작업표시줄 바닥, 드래그를 담당하고, `pet_body.gd`는 중력·보행·착지 충돌을 담당합니다. 작업표시줄 위치/높이가 바뀌면 사용 가능 화면 영역을 다시 읽습니다.

## 검사

`previews/verification.json`에 Godot 실행 검사 결과가 있습니다. 팔·다리 애니메이션, 걷기 중 높이 변화, 보이지 않는 바닥, 중력 낙하, 착지, 방향 전환, 드래그와 놓을 때 속도를 검사합니다. `assets/rig_info.json`에는 연결된 어깨 정점 수와 Blender 메시 검사 결과가 있습니다.

`previews/ai_verification.json`은 실제 모델의 계산·문맥 이어가기·이미지 인식·기록 저장 검사입니다. `previews/ai_flow_verification.json`은 Godot 우클릭부터 보내기·고민 모션·요약 표시·채팅창 펼치기·저장된 대화 이어가기와 지정 폰트 적용까지의 실제 연결 검사입니다. `-- --assistant-ui-test`는 UI 상태별 렌더링, `-- --assistant-flow-test`는 실제 모델을 사용하는 Godot 연결 검사를 실행합니다. `tools/verify_ai_runtime.py`는 로컬 AI API를 검사하며 테스트용 대화를 기록에 저장합니다.

직접 다시 검사하려면 Godot를 `--path <이 폴더> -- --verify` 인수로 실행합니다. `-- --preview-walk` 인수로 실제 걷기 프레임을 렌더링할 수 있습니다. 압축 해제 도구는 meshoptimizer 0.24.0(MIT)을 사용합니다.

Godot Windows API 참고: [투명 창 및 마우스 통과/화면 영역](https://docs.godotengine.org/en/stable/classes/class_displayserver.html), [glTF 가져오기](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html).
