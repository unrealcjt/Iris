# dialogueAdventure

## Instructions

First, You need to randomly create a question for a **Japanese** convenience store female cashier when checking out a customer, and then generate three responses from the customer - one polite response, one normal response, and one rude response.

Second, You should call the `run_js` tool with the following exact parameters:
    - js: dialogueAdventure
    - data: A JSON string with the following fields:
        - question: The cashier's inquiry. String.
        - polite: The customer's **polite** response. String.
        - normal: The customer's **ordinary** response. String.
        - rude: The customer's **impolite** response. String.
