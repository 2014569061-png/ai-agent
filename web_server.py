import http.server
import socketserver
import os
import sys
import webbrowser
import threading
import time

class MyHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        super().end_headers()

def open_browser(port):
    time.sleep(1.2)
    url = f'http://localhost:{port}'
    print(f'\n[✓] 正在自动打开浏览器: {url}')
    webbrowser.open(url)

def main():
    # 切换工作目录到 build/web
    base_dir = os.path.dirname(os.path.abspath(__file__))
    web_dir = os.path.join(base_dir, 'mobile_agent', 'build', 'web')
    
    if not os.path.exists(web_dir):
        # 兼容在 mobile_agent 目录下运行
        web_dir = os.path.join(base_dir, 'build', 'web')
    
    if not os.path.exists(web_dir):
        print(f'[!] 错误: 未找到 Web 产物目录 ({web_dir})')
        print('[!] 请先运行 flutter build web 编译项目！')
        input('按回车键退出...')
        sys.exit(1)
        
    os.chdir(web_dir)
    port = 8080
    
    for p in range(8080, 8090):
        try:
            handler = MyHTTPRequestHandler
            socketserver.TCPServer.allow_reuse_address = True
            httpd = socketserver.TCPServer(('', p), handler)
            port = p
            break
        except OSError:
            continue

    print('=' * 55)
    print('       🚀 NEXUS Agent Web 本地服务已启动')
    print('=' * 55)
    print(f' * 访问地址: http://localhost:{port}')
    print(' * Web WASM 跨域隔离支持: 已启用 (COOP/COEP)')
    print(' * 提示: 按 Ctrl + C 可停止服务')
    print('=' * 55)

    threading.Thread(target=open_browser, args=(port,), daemon=True).start()

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print('\n服务已停止。')
        httpd.server_close()

if __name__ == '__main__':
    main()
