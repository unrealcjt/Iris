// 全局游戏状态数据
let gameState = {
    question: "",
    answers: {
        polite: "",
        normal: "",
        rude: ""
    },
    timer: null,
    startTime: 0,
    isEnded: false,
    isRushed: false // 增加标记位，防止重复触发催促
};

/**
 * 接收来自 Gemma 模型的初始化参数
 * 数据格式约定：
 * {
 * "question": "...",
 * "polite": "...",
 * "normal": "...",
 * "rude": "..."
 * }
 */
window.onReceiveModelAction = function(jsonData) {
    try {
        const data = typeof jsonData === 'string' ? JSON.parse(jsonData) : jsonData;
        gameState.question = data.question;
        gameState.answers['polite'] = data.polite;
        gameState.answers['normal'] = data.normal;
        gameState.answers['rude'] = data.rude;
        gameState.isEnded = false;
        gameState.isRushed = false;

        // 初始化视觉状态
        const bgUrl = 'images/convi_normal.png';
        const gameContainer = document.getElementById('game-container');
        gameContainer.style.backgroundImage = `url('${bgUrl}')`;
        document.getElementById('question-text').innerText = gameState.question;

        // 动态自适应高度：加载图片获取比例
        const img = new Image();
        img.onload = function() {
            const ratio = img.naturalHeight / img.naturalWidth;
            const width = window.innerWidth || document.documentElement.clientWidth;
            if (width > 0 && ratio > 0) {
                const targetHeight = width * ratio;
                console.log(`更新高度: ${targetHeight} (比例: ${ratio})`);
                if (window.FlutterAgentBridge) {
                    window.FlutterAgentBridge.postMessage(JSON.stringify({
                        action: "update_height",
                        height: targetHeight
                    }));
                }
            }
        };
        img.src = bgUrl;
        // 如果图片已缓存，手动触发一次比例计算
        if (img.complete) img.onload();

        // 渲染选项内容（临时打乱顺序防止位置固定）
        const optKeys = ['polite', 'normal', 'rude'];
        optKeys.sort(() => Math.random() - 0.5); // 随机混淆

        const container = document.getElementById('options-container');
        container.innerHTML = ''; // 清空旧数据
        optKeys.forEach(key => {
            const div = document.createElement('div');
            div.className = 'option-card';
            div.innerText = gameState.answers[key];
            div.onclick = () => selectOption(key);
            container.appendChild(div);
        });

        // 重置 UI
        document.getElementById('start-btn').style.display = 'block';
        container.style.display = 'none';
        document.getElementById('result-overlay').style.display = 'none';
        stopAllAudio();
    } catch(e) {
        console.error("加载便利店数据错误: ", e);
    }
};

/**
 * 用户点击“来店（开始）”
 */
function startGame() {
    // 🔓 关键修复：预先解锁所有音频（在用户点击事件中触发）
    ['snd-rush', 'snd-happy', 'snd-normal', 'snd-angry'].forEach(id => {
        const aud = document.getElementById(id);
        if (aud) {
            // 播放一瞬间并暂停，使后续定时器可以自由播放
            aud.play().then(() => {
                aud.pause();
                aud.currentTime = 0;
            }).catch(() => {});
        }
    });

    document.getElementById('start-btn').style.display = 'none';
    document.getElementById('options-container').style.display = 'flex';

    gameState.startTime = Date.now();
    startCountdown();
}

/**
 * 启动双阶核心定时器
 */
function startCountdown() {
    if (gameState.timer) clearInterval(gameState.timer);

    gameState.timer = setInterval(() => {
        const elapsed = Math.floor((Date.now() - gameState.startTime) / 1000);

        if (elapsed === 5 && !gameState.isEnded && !gameState.isRushed) {
            // 🛑 满5秒未作答：播放催促语音，背景闪红光
            gameState.isRushed = true; // 立即锁定，防止下个 200ms 再次触发
            playAudio('snd-rush');
            const flash = document.getElementById('danger-flash');
            if (flash) {
                flash.style.animation = "flashAnimation 1s infinite";
                flash.style.opacity = "1";
            }
        }
        else if (elapsed >= 20) {
            // 🛑 满10秒超时：直接判为失败流程
            clearInterval(gameState.timer);
            if (!gameState.isEnded) handleGameOver('timeout');
        }
    }, 200);
}

/**
 * 用户做出选择
 */
async function selectOption(type) {
    if (gameState.isEnded) return;
    clearInterval(gameState.timer); // 关掉定时器
    gameState.isEnded = true;

    // 关闭红光闪烁
    const flash = document.getElementById('danger-flash');
    flash.style.animation = "none";
    flash.style.opacity = "0";

    document.getElementById('options-container').style.display = 'none';

    if (type === 'rude') {
        // 选择失礼：同超时流程一致
        await handleGameOver('rude');
    } else if (type === 'normal') {
        // 选择普通
        document.getElementById('game-container').style.backgroundImage = "url('images/convi_normal.png')";
        await playAudio('snd-normal');
        showScreenOverlay("顺利", "普通の対応（标准通过）", "rgba(255, 255, 255, 0.05)", "#38bdf8");
    } else if (type === 'polite') {
        // 选择礼貌
        document.getElementById('game-container').style.backgroundImage = "url('images/convi_happy.png')";
        await playAudio('snd-happy');
        showScreenOverlay("成功", "素晴らしいマナー！（完美礼仪！）", "rgba(16, 185, 129, 0.1)", "#34d399");
    }
}

/**
 * 失败逻辑处理器（合并失礼回答与超时）
 */
async function handleGameOver(reason) {
    gameState.isEnded = true;
    document.getElementById('options-container').style.display = 'none';

    // 关闭红光闪烁
    const flash = document.getElementById('danger-flash');
    flash.style.animation = "none";
    flash.style.opacity = "0";

    // 变更为愤怒背景、播放呵斥
    document.getElementById('game-container').style.backgroundImage = "url('images/convi_angry.png')";
    await playAudio('snd-angry');

    const descText = reason === 'timeout' ? "時間切れ（操作超时，店员暴怒）" : "大変失礼な対応（极度失礼）";
    // 展现灰色半透明遮罩与大字
    showScreenOverlay("失败", descText, "rgba(31, 41, 55, 0.65)", "#ef4444");
}

/**
 * 动画渲染结算弹窗
 */
function showScreenOverlay(title, desc, bgColor, titleColor) {
    const overlay = document.getElementById('result-overlay');
    const tWidget = document.getElementById('result-title');
    const dWidget = document.getElementById('result-desc');

    overlay.style.display = 'flex';
    overlay.style.backgroundColor = bgColor;
    overlay.style.backdropFilter = "blur(8px)";

    tWidget.innerText = title;
    tWidget.style.color = titleColor;
    dWidget.innerText = desc;

    // 异步触发渐入与缩放动画
    setTimeout(() => {
        overlay.style.opacity = "1";
        tWidget.style.transform = "scale(1)";
    }, 50);
}

/**
 * 辅助：音频播放与重置（返回 Promise 以便等待播放完成）
 */
function playAudio(id) {
    return new Promise((resolve) => {
        stopAllAudio();
        const aud = document.getElementById(id);
        if(!aud) {
            resolve();
            return;
        }

        // 播放结束时的回调
        const onEnded = () => {
            aud.removeEventListener('ended', onEnded);
            resolve();
        };
        aud.addEventListener('ended', onEnded);

        aud.currentTime = 0;
        aud.play().catch(e => {
            console.warn(`音频播放受限 [${id}]: `, e.name, e.message);
            aud.removeEventListener('ended', onEnded);
            resolve(); // 播放受限时直接继续，防止 UI 卡死
        });
    });
}

function stopAllAudio() {
    ['snd-rush', 'snd-happy', 'snd-normal', 'snd-angry'].forEach(id => {
        const aud = document.getElementById(id);
        if(aud) { aud.pause(); aud.currentTime = 0; }
    });
}

/**
 * 退出图标通知 Flutter
 */
function triggerExit() {
    clearInterval(gameState.timer);
    if (window.FlutterAgentBridge) {
        window.FlutterAgentBridge.postMessage(JSON.stringify({ action: "exit_roleplay" }));
    }
}