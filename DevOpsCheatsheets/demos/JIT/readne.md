
Example payload for JIRA issues JIT request

```json
{
    "communication": {
        "destination": {{issue.customfield_10197}},
        "method": {{issue.customfield_10198}}
    },
    "created_at": {{issue.created}},
    "created_by": {{creator.displayName}},
    "name": "Approval Request",
    "org": {{issue.customfield_10196}},
    "USER_EMAIL": {{creator.emailAddress}},
    "purpose": {{issue.customfield_10195}},
    "request_id": {{issue.url}}, 
    "policy_json": {
{{issue.customfield_10194}} 
},
    "ttl": {{issue.customfield_10193}},
    "source": {{issue.customfield_10192}}
}

```