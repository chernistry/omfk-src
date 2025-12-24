# Prompt for Dataset Search Agent

Find publicly available datasets suitable for training a **keyboard layout detection** model for the OMFK project. The model needs to recognize when text was typed on the wrong keyboard layout (e.g., Russian text typed on English keyboard produces "ghbdtn" instead of "привет").

## Requirements

### Languages Needed:
- **Russian** (Cyrillic)
- **English** (Latin)
- **Hebrew**

### Dataset Types Needed:

1. **Conversational/Informal Text**
   - Chat logs, social media posts, forum discussions
   - Should include slang, typos, abbreviations
   - Examples: OpenSubtitles, Tatoeba, Reddit dumps

2. **Short Text/Sentences**
   - Sentences under 50 words
   - Good for single-word and phrase detection
   - Examples: News headlines, tweets

3. **Mixed Script Text**
   - Text that naturally mixes multiple languages
   - Helps model distinguish legitimate mixing from layout errors

### Dataset Sources to Check:

1. **Hugging Face Datasets**
   - https://huggingface.co/datasets
   - Search for: Russian, Hebrew, multilingual

2. **OPUS Corpus**
   - https://opus.nlpl.eu/
   - OpenSubtitles, Wikipedia, news

3. **Common Crawl**
   - https://commoncrawl.org/
   - Web text (needs heavy filtering)

4. **Language-Specific**:
   - Russian: https://ruscorpora.ru/ (National Corpus)
   - Hebrew: https://github.com/NLPH/NLPH_Resources

5. **Tatoeba**
   - https://tatoeba.org/en/downloads
   - Short sentences with translations

### Output Format Needed:

Plain text files, one sentence/phrase per line:
```
ru.txt: привет как дела
        всё отлично спасибо
        ...
en.txt: hello how are you
        everything is fine thanks
        ...
he.txt: שלום מה נשמע
        הכל טוב תודה
        ...
```

### Important Considerations:

1. **License**: Must be OK for research/personal use
2. **Size**: 100MB+ per language preferred
3. **Quality**: Prefer curated over raw web scrapes
4. **Encoding**: UTF-8
5. **Freshness**: Modern text (post-2010) preferred for slang/informal

### Deliverables:

Return a list of datasets with:
- Name and URL
- Size (approximate)
- Content type (conversational, news, wiki, etc.)
- License
- Download instructions
