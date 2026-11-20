// SPDX-License-Identifier: GPL-3.0-or-later
// Extension-owned diagnostic UI. Does not emulate filtering or alter browser APIs.
const state = document.querySelector('#state');
async function poll() {
    let result;
    try { result = await browser.runtime.sendMessage({ reynardPort: 'status' }); }
    catch (error) { result = { diagnosticMessageError: String(error) }; }
    state.textContent = JSON.stringify(result, null, 2);
    window.webkit?.messageHandlers?.deviceStatus?.postMessage(result ?? { noResponse: true });
    setTimeout(poll, 1000);
}
poll();
browser.storage.local.get('user-filters').then(value => {
    document.querySelector('#filters').value = value['user-filters'] || '';
}).catch(error => { document.querySelector('#result').textContent = String(error); });
document.querySelector('#save').addEventListener('click', async () => {
    const result = document.querySelector('#result');
    try {
        const text = document.querySelector('#filters').value;
        if (text.length > 100000) throw Error('Test input too large');
        await browser.storage.local.set({ 'user-filters': text });
        result.textContent = '存储写入成功，尚不能算规则生效。等待 onChanged 编译并检查 network 和 conversion。后台重启可能重置这些测试配置。';
    } catch (error) { result.textContent = String(error); }
});
