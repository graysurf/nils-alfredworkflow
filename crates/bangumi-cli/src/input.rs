use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SubjectType {
    All,
    Book,
    Anime,
    Music,
    Game,
    Real,
}

impl SubjectType {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::All => "all",
            Self::Book => "book",
            Self::Anime => "anime",
            Self::Music => "music",
            Self::Game => "game",
            Self::Real => "real",
        }
    }

    pub const fn as_bangumi_type(self) -> Option<u8> {
        match self {
            Self::All => None,
            Self::Book => Some(1),
            Self::Anime => Some(2),
            Self::Music => Some(3),
            Self::Game => Some(4),
            Self::Real => Some(6),
        }
    }

    pub fn from_bangumi_type(raw: u8) -> Option<Self> {
        match raw {
            1 => Some(Self::Book),
            2 => Some(Self::Anime),
            3 => Some(Self::Music),
            4 => Some(Self::Game),
            6 => Some(Self::Real),
            _ => None,
        }
    }

    pub fn parse_token(raw: &str) -> Option<Self> {
        match raw.trim().to_ascii_lowercase().as_str() {
            "all" => Some(Self::All),
            "book" | "books" => Some(Self::Book),
            "anime" => Some(Self::Anime),
            "music" => Some(Self::Music),
            "game" | "games" => Some(Self::Game),
            "real" | "live" => Some(Self::Real),
            _ => None,
        }
    }
}

impl std::fmt::Display for SubjectType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedInput {
    pub subject_type: SubjectType,
    pub keyword: String,
}

pub fn parse_query_input(raw_input: &str) -> Result<ParsedInput, InputError> {
    let input = raw_input.trim();
    if input.is_empty() {
        return Err(InputError::EmptyInput);
    }

    if let Some(stripped) = input.strip_prefix('[')
        && let Some((token, rest)) = stripped.split_once(']')
    {
        let subject_type = parse_type_token(token)?;
        let keyword = rest.trim();
        if keyword.is_empty() {
            return Err(InputError::MissingQueryAfterType(format!("[{}]", token)));
        }

        return Ok(ParsedInput {
            subject_type,
            keyword: keyword.to_string(),
        });
    }

    if let Some((prefix, rest)) = input.split_once(':') {
        let prefix = prefix.trim();
        if !prefix.is_empty()
            && !prefix.contains(char::is_whitespace)
            && let Some(subject_type) = SubjectType::parse_token(prefix)
        {
            let keyword = rest.trim();
            if keyword.is_empty() {
                return Err(InputError::MissingQueryAfterType(prefix.to_string()));
            }

            return Ok(ParsedInput {
                subject_type,
                keyword: keyword.to_string(),
            });
        }
    }

    let mut parts = input.split_whitespace();
    let first = parts.next().expect("input is non-empty");

    if let Some(subject_type) = SubjectType::parse_token(first) {
        let keyword = parts.collect::<Vec<_>>().join(" ");
        if keyword.is_empty() {
            return Err(InputError::MissingQueryAfterType(first.to_string()));
        }

        return Ok(ParsedInput {
            subject_type,
            keyword,
        });
    }

    Ok(ParsedInput {
        subject_type: SubjectType::All,
        keyword: input.to_string(),
    })
}

pub fn parse_type_token(raw_type: &str) -> Result<SubjectType, InputError> {
    let trimmed = raw_type.trim();
    if trimmed.is_empty() {
        return Err(InputError::InvalidTypeToken(trimmed.to_string()));
    }

    SubjectType::parse_token(trimmed)
        .ok_or_else(|| InputError::InvalidTypeToken(trimmed.to_ascii_lowercase()))
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum InputError {
    #[error("query must not be empty")]
    EmptyInput,
    #[error("invalid type token: {0} (expected all/book/anime/music/game/real)")]
    InvalidTypeToken(String),
    #[error("missing query text after type token: {0}")]
    MissingQueryAfterType(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn input_parser_maps_supported_subject_types_to_bangumi_values() {
        let cases = vec![
            ("all", SubjectType::All, None),
            ("book", SubjectType::Book, Some(1)),
            ("anime", SubjectType::Anime, Some(2)),
            ("music", SubjectType::Music, Some(3)),
            ("game", SubjectType::Game, Some(4)),
            ("real", SubjectType::Real, Some(6)),
        ];

        for (token, expected, expected_api_type) in cases {
            let parsed = parse_type_token(token).expect("type should parse");
            assert_eq!(parsed, expected);
            assert_eq!(parsed.as_bangumi_type(), expected_api_type);
        }
    }

    #[test]
    fn input_parser_supports_bracketless_type_prefix_in_query_mode() {
        let parsed = parse_query_input("anime naruto").expect("query should parse");

        assert_eq!(parsed.subject_type, SubjectType::Anime);
        assert_eq!(parsed.keyword, "naruto");
    }

    #[test]
    fn input_parser_supports_colon_type_prefix_in_query_mode() {
        let parsed = parse_query_input("music: cowboy bebop").expect("query should parse");

        assert_eq!(parsed.subject_type, SubjectType::Music);
        assert_eq!(parsed.keyword, "cowboy bebop");
    }

    #[test]
    fn input_parser_supports_colon_type_prefix_with_surrounding_whitespace() {
        let parsed = parse_query_input("music : cowboy bebop").expect("query should parse");

        assert_eq!(parsed.subject_type, SubjectType::Music);
        assert_eq!(parsed.keyword, "cowboy bebop");
    }

    #[test]
    fn input_parser_supports_bracket_type_prefix_in_query_mode() {
        let parsed = parse_query_input("[game] zelda").expect("query should parse");

        assert_eq!(parsed.subject_type, SubjectType::Game);
        assert_eq!(parsed.keyword, "zelda");
    }

    #[test]
    fn input_parser_defaults_to_all_type_when_prefix_not_present() {
        let parsed = parse_query_input("fate stay night").expect("query should parse");

        assert_eq!(parsed.subject_type, SubjectType::All);
        assert_eq!(parsed.keyword, "fate stay night");
    }

    #[test]
    fn input_parser_treats_unknown_colon_prefix_as_plain_query() {
        let parsed = parse_query_input("fate:zero").expect("query should parse");

        assert_eq!(parsed.subject_type, SubjectType::All);
        assert_eq!(parsed.keyword, "fate:zero");
    }

    #[test]
    fn input_parser_rejects_missing_query_after_type_token() {
        let err = parse_query_input("anime").expect_err("query should fail");

        assert_eq!(err, InputError::MissingQueryAfterType("anime".to_string()));
    }

    #[test]
    fn input_parser_rejects_invalid_type_token() {
        let err = parse_type_token("manga").expect_err("invalid type should fail");

        assert_eq!(
            err,
            InputError::InvalidTypeToken("manga".to_string()),
            "invalid token should be preserved in error"
        );
    }

    #[test]
    fn input_parser_rejects_empty_query_input() {
        let err = parse_query_input(" \t ").expect_err("empty query should fail");

        assert_eq!(err, InputError::EmptyInput);
    }

    #[test]
    fn input_parser_parses_legacy_alias_tokens_case_insensitively() {
        let books = parse_query_input("Books fullmetal").expect("books alias should parse");
        assert_eq!(books.subject_type, SubjectType::Book);

        let games = parse_query_input("GaMeS zelda").expect("games alias should parse");
        assert_eq!(games.subject_type, SubjectType::Game);

        let live = parse_query_input("live tokyo").expect("live alias should parse");
        assert_eq!(live.subject_type, SubjectType::Real);
    }
}
