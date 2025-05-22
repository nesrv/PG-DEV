from re import *


with open("etc//1.2.md", encoding='utf-8') as textfile:
    text = textfile.read()

    template = r"\n\d+:\d\d\n"

    result = sub(template, " ", text)
    print(result)
    # print(text.replace("\n", " "))

with open("etc//1.2.md", 'w',encoding='utf-8') as textfile:
    textfile.write(result)