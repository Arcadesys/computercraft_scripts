import re,sys
p=r'c:/Users/auste/OneDrive/Documents/computercraft/branchminer.lua'
with open(p,'r',encoding='utf-8') as f:
    lines=f.readlines()
stack=[]
for i,l in enumerate(lines,1):
    code=re.sub(r"--.*","",l)
    tokens=re.findall(r"\b(function|do|if|for|repeat|end)\b",code)
    for t in tokens:
        if t in ('function','do','if','for','repeat'):
            stack.append((t,i,l.rstrip()))
        elif t=='end':
            if stack:
                stack.pop()
            else:
                print(f"Unmatched end at {i}: {l.rstrip()}")
                sys.exit(0)
if stack:
    print('Unclosed blocks (top->bottom):')
    for t,i,l in stack[-60:]:
        print(f"{t} opened at line {i}: {l}")
    sys.exit(1)
print('All blocks closed')
