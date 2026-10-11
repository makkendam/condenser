#include "qvdfparser.h"

#include <QFile>

QVdfParser::VdfObject *QVdfParser::VdfObject::child(const QString &name) const
{
    for (VdfObject *child : m_children) {
        if (child->name() == name) {
            return child;
        }
    }
    return nullptr;
}

QVdfParser::VdfObject *QVdfParser::VdfObject::childByPath(const QString &path) const
{
    const QStringList segments = path.split(QLatin1Char('/'), Qt::SkipEmptyParts);
    if (segments.isEmpty()) {
        return nullptr;
    }
    const VdfObject *current = this;
    for (const QString &segment : segments) {
        current = current->child(segment);
        if (!current) {
            return nullptr;
        }
    }
    return const_cast<VdfObject *>(current);
}

std::unique_ptr<QVdfParser::VdfObject> QVdfParser::parseFile(const QString &filePath)
{
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        m_lastError = QStringLiteral("Cannot open file: %1").arg(filePath);
        return nullptr;
    }
    return parse(QString::fromUtf8(file.readAll()));
}

std::unique_ptr<QVdfParser::VdfObject> QVdfParser::parse(const QString &content)
{
    m_lastError.clear();
    int pos = 0;
    try {
        // "RootName" { ... }
        skipWhitespaceAndComments(content, pos);
        if (pos >= content.length()) {
            throw QStringLiteral("Empty VDF content");
        }
        auto root = std::make_unique<VdfObject>(readString(content, pos));
        skipWhitespaceAndComments(content, pos);
        if (pos >= content.length() || content[pos] != QLatin1Char('{')) {
            throw QStringLiteral("Expected '{' after the root name");
        }
        ++pos;
        parseSection(root.get(), content, pos);
        return root;
    } catch (const QString &error) {
        m_lastError = error;
        return nullptr;
    }
}

void QVdfParser::parseSection(VdfObject *object, const QString &content, int &pos) const
{
    while (true) {
        skipWhitespaceAndComments(content, pos);
        if (pos >= content.length()) {
            throw QStringLiteral("Missing closing brace");
        }
        if (content[pos] == QLatin1Char('}')) {
            ++pos;
            return;
        }

        const QString key = readString(content, pos);
        if (key.isEmpty()) {
            throw QStringLiteral("Empty key");
        }
        skipWhitespaceAndComments(content, pos);
        if (pos >= content.length()) {
            throw QStringLiteral("Unexpected end after key");
        }

        if (content[pos] == QLatin1Char('{')) {
            ++pos;
            auto child = std::make_unique<VdfObject>(key);
            parseSection(child.get(), content, pos);
            object->addChild(child.release());
        } else {
            object->addAttribute(key, readString(content, pos));
        }
    }
}

void QVdfParser::skipWhitespaceAndComments(const QString &content, int &pos)
{
    const int length = content.length();
    while (pos < length) {
        if (content[pos].isSpace()) {
            ++pos;
        } else if (content[pos] == QLatin1Char('/') && pos + 1 < length && content[pos + 1] == QLatin1Char('/')) {
            while (pos < length && content[pos] != QLatin1Char('\n')) {
                ++pos;
            }
        } else {
            return;
        }
    }
}

// A quoted string (with \" and \\ escapes) or a bare word
QString QVdfParser::readString(const QString &content, int &pos)
{
    const int length = content.length();
    QString result;

    if (content[pos] != QLatin1Char('"')) {
        while (pos < length && !content[pos].isSpace() && content[pos] != QLatin1Char('{')
               && content[pos] != QLatin1Char('}') && content[pos] != QLatin1Char('"')) {
            result += content[pos++];
        }
        return result;
    }

    ++pos; // Opening quote
    while (pos < length) {
        const QChar c = content[pos++];
        if (c == QLatin1Char('"')) {
            return result;
        }
        if (c == QLatin1Char('\\') && pos < length) {
            result += content[pos++];
        } else {
            result += c;
        }
    }
    throw QStringLiteral("Unterminated quoted string");
}
