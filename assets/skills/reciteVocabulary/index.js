// 全局状态管理
let wordList = [
    {"japanese": "綺麗", "chinese": "美丽、干净"},
    {"japanese": "賑やか", "chinese": "热闹、繁华"}
];
let currentIndex = 0;

/**
 * 核心接口：接收来自本地大模型（Gemma）处理后的 10 个词对
 * 期望传入的结构：
 * [
 * {"japanese": "綺麗", "chinese": "美丽、干净"},
 * {"japanese": "賑やか", "chinese": "热闹、繁华"},
 * ... (共10个)
 * ]
 */
window.onReceiveModelAction = function(jsonData) {
    try {
        wordList = JSON.parse(jsonData);
        currentIndex = 0;

        if (wordList && wordList.length > 0) {
            renderCard();
        } else {
            document.getElementById('display-japanese').innerText = "暂无生词";
        }
    } catch (e) {
        document.getElementById('display-japanese').innerText = "数据解析有误";
        console.error("解析模型词对 JSON 错误: ", e);
    }
};

/**
 * 执行渲染当前位置的卡片
 */
function renderCard() {
    const cardInner = document.getElementById('card-inner');
    const prevBtn = document.getElementById('btn-prev');
    const nextBtn = document.getElementById('btn-next');

    // 1. 切换新词之前，如果当前卡片是翻开的，强制重置回正面（防穿帮）
    cardInner.classList.remove('is-flipped');

    // 2. 延迟注入文本内容，等重置正面的动画做完（体验更平滑）
    setTimeout(() => {
        const currentWord = wordList[currentIndex];
        document.getElementById('display-japanese').innerText = currentWord.japanese;
        document.getElementById('display-chinese').innerText = currentWord.chinese;
        document.getElementById('progress-indicator').innerText = `${currentIndex + 1} / ${wordList.length}`;
    }, 150);

    // 3. 动态调整底部导航按钮的禁用状态边界
    prevBtn.disabled = (currentIndex === 0);
    nextBtn.disabled = (currentIndex === wordList.length - 1);
}

/**
 * 点击卡片触发 3D 翻转
 */
function flipCard() {
    const cardInner = document.getElementById('card-inner');
    cardInner.classList.toggle('is-flipped');
}

/**
 * 切换到上一个单词
 */
function prevCard() {
    if (currentIndex > 0) {
        currentIndex--;
        renderCard();
    }
}

/**
 * 切换到下一个单词
 */
function nextCard() {
    if (currentIndex < wordList.length - 1) {
        currentIndex++;
        renderCard();
    }
}

/**
 * 退出背词组件，通知 Flutter 解除当前 Agent 独占状态
 */
function triggerExit() {
    if (window.FlutterAgentBridge) {
        const exitSignal = JSON.stringify({ action: "exit_word_mode" });
        window.FlutterAgentBridge.postMessage(exitSignal);
    }
}