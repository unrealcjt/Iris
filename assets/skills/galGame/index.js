/**
 * 监听大模型（Gemma）传过来的参数
 */
window.onReceiveModelAction = function(jsonData) {
    const data = JSON.parse(jsonData);

    // 1. 切换背景立绘
    const bgImage = document.getElementById('bg-image');
    bgImage.onload = function() {
        notifyHeight();
    };
    bgImage.src = `images/character_${data.emotion}.png`;

    // 2. 写入中文翻译，并强制重置为【默认隐藏】状态
    const translationElement = document.getElementById('translation');
    translationElement.innerText = data.translation;
    translationElement.style.display = 'none';
    updateTranslateIcon(false); // 图标重置为普通未激活状态

    // 3. 居中台词的打字机特效
    const textElement = document.getElementById('text');
    textElement.innerText = data.reply;
//    textElement.innerText = '';
//    let index = 0;
//
//    function typeWriter() {
//        if (index < data.reply.length) {
//            textElement.innerText += data.reply.charAt(index);
//            index++;
//            setTimeout(typeWriter, 40);
//        }
//    }
    // typeWriter();
};

/**
 * 切换翻译的显示与隐藏
 */
function toggleTranslation() {
    const translationElement = document.getElementById('translation');

    if (translationElement.style.display === 'none' || translationElement.style.display === '') {
        translationElement.style.display = 'block';
        updateTranslateIcon(true);  // 切换为激活状态（高亮粉色）
    } else {
        translationElement.style.display = 'none';
        updateTranslateIcon(false); // 切换为未激活状态（白色）
    }
}

/**
 * 辅助函数：更新翻译图标的视觉状态
 */
function updateTranslateIcon(isActive) {
    const btn = document.getElementById('translate-toggle-btn');
    const iconSvg = document.getElementById('translate-icon');
    if (isActive) {
        btn.style.opacity = '1';
        iconSvg.style.stroke = '#ff69b4'; // 显示翻译时图标高亮粉色
    } else {
        btn.style.opacity = '0.6';
        iconSvg.style.stroke = '#ffffff'; // 隐藏翻译时恢复初始白色
    }
}

/**
 * 点击左上角退出按钮时触发
 */
function triggerExit() {
    if (window.FlutterAgentBridge) {
        const exitSignal = JSON.stringify({ action: "exit_roleplay" });
        window.FlutterAgentBridge.postMessage(exitSignal);
    }
}

/**
 * 通知 Flutter 容器高度变化
 */
function notifyHeight() {
    const container = document.getElementById('game-container');
    if (container && window.FlutterAgentBridge) {
        // 使用 getBoundingClientRect 获取精确的像素高度
        const rect = container.getBoundingClientRect();
        window.FlutterAgentBridge.postMessage(JSON.stringify({
            action: "update_height",
            height: rect.height
        }));
    }
}

// 初始加载时通知高度
window.addEventListener('load', () => {
    const bgImage = document.getElementById('bg-image');
    if (bgImage && bgImage.complete) {
        notifyHeight();
    } else if (bgImage) {
        bgImage.onload = notifyHeight;
    }
});
