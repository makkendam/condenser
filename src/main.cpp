#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QIcon>
#include <QDir>
#include <QStandardPaths>

#ifdef HAVE_KICONTHEME
#include <KIconTheme>
#endif // HAVE_KICONTHEME

#include "steamrecordingmanager.h"
#include "systemchecker.h"
#include "videoexporter.h"
#include "gameinfo.h"
#include "recordingclip.h"
#include "recordingfiltermodel.h"

int main(int argc, char *argv[])
{
#ifdef HAVE_KICONTHEME
    KIconTheme::initTheme();
#endif // HAVE_KICONTHEME

    QGuiApplication app(argc, argv);

    // Set application properties
    app.setApplicationName("Pineapple Steam Recording Exporter");
    app.setApplicationVersion(QStringLiteral(PSRE_VERSION));

    // Set application icon
    app.setWindowIcon(QIcon(":/qml/app_icon.png"));



    // Use Material Design style
    QQuickStyle::setStyle("Material");

    // Create QML engine
    QQmlApplicationEngine engine;

    // Register C++ types for QML
    qmlRegisterType<SteamRecordingManager>("net.blumia.pineapple.streamrecordingexporter", 1, 0, "SteamRecordingManager");
    qmlRegisterType<SystemChecker>("net.blumia.pineapple.streamrecordingexporter", 1, 0, "SystemChecker");
    qmlRegisterType<VideoExporter>("net.blumia.pineapple.streamrecordingexporter", 1, 0, "VideoExporter");
    qmlRegisterType<RecordingClip>("net.blumia.pineapple.streamrecordingexporter", 1, 0, "RecordingClip");
    qmlRegisterType<RecordingFilterModel>("net.blumia.pineapple.streamrecordingexporter", 1, 0, "RecordingFilterModel");

    // Create and expose global instances to QML
    SystemChecker systemChecker;
    SteamRecordingManager recordingManager;
    VideoExporter videoExporter;

    engine.rootContext()->setContextProperty("systemChecker", &systemChecker);
    engine.rootContext()->setContextProperty("recordingManager", &recordingManager);
    engine.rootContext()->setContextProperty("videoExporter", &videoExporter);

    // Set up QML import paths
    engine.addImportPath("qrc:/");

    // Load the main QML file
    const QUrl url(QStringLiteral("qrc:/net/blumia/pineapple/streamrecordingexporter/qml/main.qml"));

    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl) {
            QCoreApplication::exit(-1);
        }
    }, Qt::QueuedConnection);

    // Connect signals for better error handling
    QObject::connect(&engine, &QQmlApplicationEngine::warnings,
                     [](const QList<QQmlError> &warnings) {
        for (const auto &warning : warnings) {
            qWarning() << "QML Warning:" << warning.toString();
        }
    });

    engine.load(url);

    if (engine.rootObjects().isEmpty()) {
        qCritical() << "Failed to load QML file:" << url;
        return -1;
    }

    // Start the application event loop
    return app.exec();
}
