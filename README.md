# EstencelWeaponFixMod
License: NYSL <http://www.kmonos.net/nysl>

- マルチプレイ時にサブ武器が別の武器に入れ替わる不具合の修正Mod

---

## 導入手順

### 1. UE4SSの導入
1. "UE4SS-RE/RE-UE4SS"リポジトリから最新版を入手
    - 動作確認済: https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v4.0.0
        - ページ下部`Assets`内: `UE4SS_v4.0.0.zip`
2. zipの中身を`Estencel\Binaries\Win64\`に展開
    - ゲームフォルダはsteamで`Estencel`->`プロパティ`->`インストール済みファイル`から飛べる
    - `Win64`下に`dwmapi.dll`, `ue4ss`フォルダが展開されていればok

### 2. Mod導入
1. 本ページ上部の`<>Code`->`Download ZIP`
2. `EstencelWeaponFix`フォルダを`ue4ss\Mods\`にコピー

---

## 削除手順
それぞれ導入したものを削除するだけでok (Steamのプロセスを終了していないと削除できないかもしれない)<br>
**ゲームのアンインストール後も残ることがあるので要確認(手動削除してください)**
- UE4SS+Mod: `dwmapi.dll`, `ue4ss` を削除
- Mod単体: `Mods\EstencelWeaponFix` フォルダのみ削除

---

## 使用方法
- 特に何もしなくても自動で動作します

---