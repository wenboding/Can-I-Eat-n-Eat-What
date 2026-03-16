import Foundation

enum JSONSchemas {
    static var mealAnalysis: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": [
                "foods",
                "calories_estimate",
                "macros_estimate",
                "diet_flags",
                "allergen_warnings",
                "notes"
            ],
            "properties": [
                "foods": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["name", "portion", "confidence"],
                        "properties": [
                            "name": ["type": "string"],
                            "portion": ["type": "string"],
                            "confidence": ["type": "number"]
                        ]
                    ]
                ],
                "calories_estimate": ["type": "number"],
                "macros_estimate": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["protein_g", "carbs_g", "fat_g"],
                    "properties": [
                        "protein_g": ["type": "number"],
                        "carbs_g": ["type": "number"],
                        "fat_g": ["type": "number"]
                    ]
                ],
                "diet_flags": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "allergen_warnings": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "notes": ["type": "string"]
            ]
        ]
    }

    static var medicalTranscript: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["raw_text"],
            "properties": [
                "raw_text": ["type": "string"]
            ]
        ]
    }

    static var recommendation: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["recommended_meal", "nearby_options"],
            "properties": [
                "recommended_meal": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": [
                        "title",
                        "why",
                        "nutrition_focus",
                        "suggested_ingredients",
                        "estimated_macros",
                        "estimated_calories"
                    ],
                    "properties": [
                        "title": ["type": "string"],
                        "why": ["type": "string"],
                        "nutrition_focus": [
                            "type": "array",
                            "items": ["type": "string"]
                        ],
                        "suggested_ingredients": [
                            "type": "array",
                            "items": ["type": "string"]
                        ],
                        "estimated_macros": [
                            "type": "object",
                            "additionalProperties": false,
                            "required": ["protein_g", "carbs_g", "fat_g"],
                            "properties": [
                                "protein_g": ["type": "number"],
                                "carbs_g": ["type": "number"],
                                "fat_g": ["type": "number"]
                            ]
                        ],
                        "estimated_calories": ["type": "number"]
                    ]
                ],
                "nearby_options": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["name", "reason", "distance_miles"],
                        "properties": [
                            "name": ["type": "string"],
                            "reason": ["type": "string"],
                            "distance_miles": ["type": "number"]
                        ]
                    ]
                ]
            ]
        ]
    }
}
