#ifndef QVDFPARSER_H
#define QVDFPARSER_H

#include <QList>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <memory>

// Reader for Steam's text VDF (KeyValues) files, such as localconfig.vdf
// and libraryfolders.vdf. Binary VDF (shortcuts.vdf) is read in gameinfo.cpp.
class QVdfParser
{
public:
    // A section: string attributes plus nested sections
    class VdfObject
    {
    public:
        VdfObject() = default;
        explicit VdfObject(const QString &name) : m_name(name) {}
        ~VdfObject() { qDeleteAll(m_children); }
        VdfObject(const VdfObject &) = delete;
        VdfObject &operator=(const VdfObject &) = delete;

        QString name() const { return m_name; }
        void setName(const QString &name) { m_name = name; }

        void addAttribute(const QString &key, const QString &value) { m_attributes[key] = value; }
        bool hasAttribute(const QString &key) const { return m_attributes.contains(key); }
        QString stringAttribute(const QString &key, const QString &defaultValue = QString()) const
        {
            return m_attributes.value(key, defaultValue).toString();
        }

        // Takes ownership
        void addChild(VdfObject *child) { m_children.append(child); }
        QList<VdfObject *> children() const { return m_children; }
        VdfObject *child(const QString &name) const;
        // e.g. "InstallConfigStore/Software/Valve/Steam"
        VdfObject *childByPath(const QString &path) const;

    private:
        QString m_name;
        QVariantMap m_attributes;
        QList<VdfObject *> m_children;
    };

    // Root section of the file, or nullptr (see lastError())
    std::unique_ptr<VdfObject> parseFile(const QString &filePath);
    std::unique_ptr<VdfObject> parse(const QString &content);

    QString lastError() const { return m_lastError; }

private:
    void parseSection(VdfObject *object, const QString &content, int &pos) const;
    static void skipWhitespaceAndComments(const QString &content, int &pos);
    static QString readString(const QString &content, int &pos);

    QString m_lastError;
};

#endif // QVDFPARSER_H
