# MarkView App Icon 設計邏輯

> **資產來源聲明 / Asset provenance**:本專案的 app icon(`Resources/AppIcon.png`
> 及由其產生的 `AppIcon.icns`)為 **AI 生成的原創圖像資產**,依本文件的設計
> brief 產出,並經人工檢查確認不近似任何既有商標(見第 8 節原創性檢查清單)。
> The app icon is an AI-generated original asset produced from the design brief
> in this document and manually reviewed for trademark originality.

## 1. 設計目標
- 讓 icon 一眼傳達「這是一個 Markdown 檢視工具」。
- 借用 Notepad++ 的精神概念（致敬），但**不得照抄**其視覺、造型或商標。
- 融入使用者的 macOS Dock，與周邊 flat icon 協調。
- 小尺寸（16–32px）仍可辨識，silhouette 要夠強。

## 2. Notepad++ 參考解構
Notepad++ 的識別核心拆成三個可借用的「概念元件」：
- 綠色主色調
- 一隻爬蟲類吉祥物（變色龍）
- 「文字／編輯器」的隱喻

策略：**保留概念層（動物吉祥物 + 文件隱喻 + 綠色起點），重造表現層**（不同動物語彙、不同造型、不同構圖），以避免商標近似。

## 3. 致敬但不照抄原則（Anti-Infringement）
- 不使用變色龍造型（無舌頭、無捲尾等變色龍專屬特徵）。
- 不複製 Notepad++ 的 logo 形狀、配色比例或版式。
- 生物改為「抽象幾何拼塊」風格，屬原創設計。
- 每次生成都要求 commercially safe、不近似任何既有商標。

## 4. 四個設計決策軸（與使用者確認）
| 決策軸 | 選項 | 定案 |
|---|---|---|
| 吉祥物 | 換一種爬蟲 / 抽象幾何生物 / 不要動物 | 抽象幾何生物 |
| Markdown 元素 | 放 MD 記號 / 純吉祥物 | 放 `M↓` 角標 |
| 配色 | 綠色系（致敬改調）/ 藍紫科技 / 多色 | 先綠後改藍（見迭代） |
| 風格 | macOS 擬物 / 扁平極簡 / 3D | 最終扁平化 |

## 5. 迭代歷程
1. **V1 擬物綠**：深黑底 + 玻璃高光 + 低多邊形綠色生物 + `M↓`。問題：放進 Dock 太突兀，與 flat icon 不協調。
2. **V2 扁平綠**：去玻璃／去深黑底，改淺綠底 flat 色塊、簡化造型。問題：色調（使用者要藍）、要去背。
3. **V3 扁平透明藍（定案）**：主色改藍色系；PNG 帶 alpha（方塊外圍透明）；保留淺藍 squircle 底（使用者選擇保留底，因無底會降低小尺寸辨識度）。

## 6. 設計元素定義（定案版）
- **主體**：抽象幾何拼塊組成的生物側臉。
- **角標**：右下 `M↓`（Markdown 記號），輕量、融入不搶主體。
- **主色**：藍色系 flat 色塊。
- **外形**：macOS squircle 圓角方磚。
- **背景**：淺藍 squircle 底 + 外圍透明（RGBA）。

## 7. 技術產製流程
1. AI 生成 1024×1024 圖稿（依上述 brief）。
2. 必要時去背／調色，確保存成**真正含 alpha 的 PNG**（注意 CDN 有時 `.png` 實為 JPEG，需 `sips -s format png` 強制轉換）。
3. `sips` 產出 iconset（16/32/128/256/512 各 @1x/@2x）。
4. `iconutil -c icns AppIcon.iconset -o AppIcon.icns`。
5. 放進 `Resources/`，`Info.plist` 設 `CFBundleIconFile`／`CFBundleIconName = AppIcon`。
6. `install.sh` 複製 `.icns` 進 app bundle 並刷新 icon cache。

## 8. 原創性檢查清單
- [ ] 非變色龍造型，無變色龍專屬特徵。
- [ ] 不近似 Notepad++ logo 的形狀／配色比例／版式。
- [ ] 生物為原創抽象設計。
- [ ] 圖稿 commercially safe。

## 9. 2026 Negative M 重設計

本輪重新提出三個彼此獨立的 flat-vector 方向：藍色文件安全款
**Blue Document**、負空間幾何款 **Negative M**、以及暖色編輯視窗款
**Editorial Viewport**。使用者選定 Negative M 作為正式 app icon。

Negative M 以深炭灰與青綠兩組幾何折帶構成緊湊的 `M` 輪廓，負空間同時暗示
向下閱讀與文件檢視。圖形不使用動物、變色龍、舌頭或捲尾元素，採透明背景、
強 silhouette 與純 flat 色塊，以維持 16–32px 小尺寸辨識度及 macOS Dock
相容性。

> **資產來源聲明 / Asset provenance**：本次 Negative M 圖稿為 AI 生成的
> 原創視覺方向，生成時明確要求 commercially safe，且不得近似任何既有品牌
> logo 或商標。正式 `Resources/AppIcon.png` 已人工移除生成圖內的偽透明棋盤格，
> 重建為 1024×1024 真正 RGBA PNG，再衍生 `AppIcon.icns`。

### Dark mode 對比修正

純透明版在深色 macOS Dock 上會讓深炭灰 M 輪廓沉入背景，因此比較了三種修正：
淺色 squircle 底板、透明背景加細淺色描邊、以及將炭灰調亮為 slate blue-gray。
最終選定方案 1「淺色 squircle 底板」，因其在明暗 Dock 上都提供最穩定的對比，
同時完整保留 Negative M 的原始幾何、深炭灰與青綠配色；底板外圍維持真透明。

### Optical size / Dock harmony

Dock 實際比較顯示原稿 alpha bounding box 佔 1024 畫布 94.63%，四邊僅約
27–28px 透明留白，視覺尺寸明顯大於相鄰 app。比較 80%、84%、88% 三個
等比例縮小候選後，選定 **84%**：最終 bbox 為 860×860（83.98%），四邊
各 82px、中心誤差 0px。這個比例在 64px／128px 仍保持 M 清晰，同時更接近
macOS Dock 的共同 optical size。調整只縮放完整 artwork 並增加透明留白，
不改 squircle、M、青綠折帶的內部比例、顏色或 alpha 關係。
