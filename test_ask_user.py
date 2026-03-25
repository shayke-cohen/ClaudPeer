import json, asyncio, websockets

async def go():
    ws = await websockets.connect('ws://localhost:9849')
    r = await ws.recv()
    print('Connected:', r[:60])

    await ws.send(json.dumps({
        'type': 'session.create',
        'conversationId': 'e2e-ask-001',
        'agentConfig': {
            'name': 'AskBot',
            'systemPrompt': 'Always use ask_user tool to ask questions. Never output questions as plain text.',
            'allowedTools': ['ask_user'],
            'mcpServers': [],
            'model': 'haiku',
            'maxTurns': 5,
            'workingDirectory': '/tmp',
            'skills': [],
            'interactive': True
        }
    }))
    await asyncio.sleep(0.5)

    await ws.send(json.dumps({
        'type': 'session.message',
        'sessionId': 'e2e-ask-001',
        'text': 'Use the ask_user tool to ask what my favorite animal is.'
    }))
    print('Sent message, waiting...')

    for _ in range(60):
        try:
            e = await asyncio.wait_for(ws.recv(), 2)
            d = json.loads(e)
            t = d.get('type', '?')
            print(f'[{t}] {e[:200]}')
            if t == 'agent.question':
                print('\n=== SUCCESS: ask_user tool was called! ===')
                break
            if t in ('session.result', 'session.error'):
                print(f'\n=== Session ended with {t} (ask_user was NOT called) ===')
                break
        except asyncio.TimeoutError:
            pass

    await ws.close()

asyncio.run(go())
