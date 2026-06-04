# reciteVocabulary

## Instructions

First, you need call the "run_intent" tool with the following exact parameters:
   - intent: getRandomVocab

By getRandomVocab you will get ten Japanese words and their corresponding English definitions. You need to convert English definition into Chinese meaning.

Second, You need to match the translated Chinese meaning with the original Japanese word, then you need invoke the `run_js` tool with the following exact parameters:
    
    - js: reciteVocabulary
    - data: A JSON string list with the following fields:
        - japanese: The Japanese word. String.
        - chinese: Corresponding Chinese meaning. String.

## Example of run_js data parameter
"[
{"japanese": "綺麗", "chinese": "美丽、干净"},
{"japanese": "賑やか", "chinese": "热闹、繁华"}
]"
You need to fill in the ACTUAL parameters based on the data obtained from **getRandomVocab**.



