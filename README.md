
Zum Ende der Metadaten springen

    Angelegt von Hans-Friedrich Pfeiffer, zuletzt geändert vor Kurzem

Zum Anfang der Metadaten
Beschreibung

Diese Dokumentation beschreibt, wie ein Repository von unbenutzten Objekten bereinigt werden kann.


Generelle Vorgehensweise zur Bereinigung eines Repositories

Für eine Bereinigung eines Repositories sollen alle Objekte ( Sources, Targets, Transformationen, Mappings, Mapplets sowie Worklets ) gelöscht werden, die nicht mehr benötigt werden.

Die Definiton von "nicht mehr benötigt" bedeutet, dass es keinübergeordnetes Informatica-Objekt mehr gibt, in welchem das zu löschende verwendet wird. Im Folgenden sprechen wir dann von freien Objekten.


Die einzelnen Objekttypen in Informatica sind hierarchisch angeordnet: Sourcen, Targets und Transformations müssen einem Mapping oder einem Mapplet zugeordnet sein, ein Mapplet muss einem Mapping, ein Mapping einem Worklet oder einem Workflow zugeordnet sein und schließlich muss ein Worklet einem Mapping zugewiesen sein. Die Reihenfolge wird bei der Bereinigung eine entscheidene Rolle spielen.

Im ersten Schritt sollten also diejenigen Workflows identifiziert und manuell gesichert und gelöscht werden, die nicht mehr verwendet werden sollen. Daraus ergibt sich dann die Liste von Mappings, Mapplets und Workflows, die nicht mehr durch einen Workflow aufgerufen werden und daher gelöscht werden können.

Sind freie Mappings ( Mapplets, Worklets ) dann gelöscht, so ergibt sich daraus die Liste der Sourcen, Targets und Transformationen, die frei geworden sind und daher ebenfalls gelöscht werden können.


Genaue Vorgehensweise
Erstellung der Liste der nicht mehr verwendeten Objekte

Die Bereinigung eines Repositories erfolgt iterativ. Es müssen nach Löschungen bestimmter Objekttype die Liste der nicht mehr verwendeten Objekte neu erstellt werden. Die Neuserstellung dieser Liste ergibt sich aus der hierarchischen Zuordnung der Objekttypen untereinander. Wir beschreiben daher die generelle Vorgehensweise, wie diese Liste erzeugt und bearbeitet werden muss:

Der Repository-Manager ist aufzurufen. Im Menü "Tools" ist das Untermenü "Queries" aufzrufen. Für jedes Repository ist dort eine Abfrage "Unused Objects" angelegt. Diese Abfrage ist auszuführen ( Button "Execute" ). Der Repository-Manager erzeugt in einem Fenster dann die Liste der nicht mehr verwendeten Objekte.

VORSICHT: leider kann nachgewiesen werden, dass diese Liste auch Objekte enthält, die sehrwohl noch gebraucht werden ( weil sie einen Parent besitzen ) - auf die Ergebnismenge ist daher nur bedingt Verlaß. Es muss daher VOR dem tatsächlichem Löschen unbedingt geprüft werden, ob es zu dem zu löschendem Objekt wirklich keine Parents gibt.

Im Menü File soll diese Liste lokal abgespeichert werden: es ist darauf zu achten, dass im Dialog als Dateity "Text Files (*.txt)" ausgewählt wird und KEINESFALLS "Web Files".

Die so erzeugte Datei ist auf den entsprechenden Server zu übertragen ( winscp ) und dort in einem geeigneten Directory abzulegen. Auf diese Datei ist dann das folgende Komando auszuführen:

cat TestDel.txt | cut -f1,3,8 -d $'\t' | sed 's/Definition//' | awk '{ printf "perl $PMExtProcDir/DeleteInformaticaObject.pl %50s %50s %50s $AUTO\n", $3, tolower($2), $1 }' | grep -i -v "User Defined\|Lookup\|Expression\|Email\|Filter\|Command\|Stored\|Aggregator\|SessionConfig\|User\|Sequence\|Scheduler\|items:\|Results\|Session\|Title:\|Name" | sort > DeleteObjects.sh


Das so erzeugte Shell-Skript DeleteObjects.sh enthält Zeilen, die etwa so aussehen:

perl $PMExtProcDir/DeleteInformaticaObject.pl HIGHUSAGE Target sc_FIL_O2_NRTR_ENDFILTER $AUTO
perl $PMExtProcDir/DeleteInformaticaObject.pl HIGHUSAGE Mapping m_O2_NRTR_HighUsage_Report_CDR $AUTO
perl $PMExtProcDir/DeleteInformaticaObject.pl ABLAUFPLAN Worklet Verträge $AUTO
perl $PMExtProcDir/DeleteInformaticaObject.pl ABLAUFPLAN Worklet wk_NBO_BESTAND_ANSPRACHE $AUTO
perl $PMExtProcDir/DeleteInformaticaObject.pl DWHBASIS_FAKTEN Source sc_FAK_VVL_ARPU $AUTO

Darin wird das Perl-Skript $PMExtProcDir/DeleteInformaticaObject.pl aufgerufen, der den Löschvorgang durchführt. Das Perl-Programm prüft hierbei, ob das zu löschende Objekt noch Parents besitzt. Children des zu löschenden Objektes, die ebenfalls frei sind ( keinen anderen Parent mehr haben ), werden dann ebenfalls gelöscht. Der letzte Parameter des perl-Skriptes darf den Wert "AutoDelete" enthalten: dann wird vor dem Löschvoirgang nicht mehr explizit abgefragt, ob eine Löschung tatsächlich durchgeführt werden soll - dies wird dann automatisch getan.

Löschungen von Objekten aus TABELLENDEFINITIONEN solten stets am ENDE der Verarbeitung stehen, da die meisten SOurcen und Tragets noch Shortcuts in andern Foldern besitzen und damit also einen Parent haben.

Wenn gewünscht ist, dass das Skript automatisch uind ohne weitere Nachfrage die Löschung durchführen soll, dann sollte im Shell-Skript DeleteObjects.sh  die Variable $AUTO wie folgt in der ersten Zeile gesetzt werden:

AUTO="AutoDelete"

export $AUTO

Ansonsten braucht nichts gemacht werden, die Variable wäre dann leer.


Nach dem Editieren des Shellskriptes kann dies dann auf Prompt aufgerufen werden.






Nicht mehr verwendete Sourcen und Shortcuts auf Sourcen

Das folgende SQL-Statement ermittelt alle Sourcen und Shortcuts auf Sourcen, die in keinem Mapping mehr verwendet werden.

select distinct subject_area, parent_source_database_name, source_name  from rep_all_source_flds
where source_id not in
(
   select source_id from REP_SRC_MAPPING
)
order by 1,2,3

Nicht mehr verwendete Targets und Shortcuts auf Targets




Nicht mehr verwendete Targets und Shortcusta auf Targest  Quelle erweitern

select distinct subject_area, target_name  from rep_all_target_flds
where target_id not in
(
   select widget_id from OPB_WIDGET_INST
)
order by 1,2

Anzeigen ungültiger Objekte
select * from
(
select 'OPB_MAPPING', count(*) anz_invalid from OPB_MAPPING where is_valid = 0 union all
select 'OPB_MAPPING_', count(*) from OPB_MAPPING_ where is_valid = 0 union all
select 'OPB_MD_CUBE', count(*) from OPB_MD_CUBE where is_valid = 0 union all
select 'OPB_MD_CUBE_', count(*) from OPB_MD_CUBE_ where is_valid = 0 union all
select 'OPB_MD_DIMENSION', count(*) from OPB_MD_DIMENSION where is_valid = 0 union all
select 'OPB_MD_DIMENSION_', count(*) from OPB_MD_DIMENSION_ where is_valid = 0 union all
select 'OPB_MD_FACT', count(*) from OPB_MD_FACT where is_valid = 0 union all
select 'OPB_MD_FACT_', count(*) from OPB_MD_FACT_ where is_valid = 0 union all
select 'OPB_MD_HIERARCHY', count(*) from OPB_MD_HIERARCHY where is_valid = 0 union all
select 'OPB_MD_HIERARCHY_', count(*) from OPB_MD_HIERARCHY_ where is_valid = 0 union all
select 'OPB_MD_LEVEL', count(*) from OPB_MD_LEVEL where is_valid = 0 union all
select 'OPB_MD_LEVEL_', count(*) from OPB_MD_LEVEL_ where is_valid = 0 union all
select 'OPB_TASK', count(*) from OPB_TASK where is_valid = 0 union all
select 'OPB_TASK_', count(*) from OPB_TASK_ where is_valid = 0 union all
select 'OPB_TASK_INST', count(*) from OPB_TASK_INST where is_valid = 0 union all
select 'OPB_TASK_INST_', count(*) from OPB_TASK_INST_ where is_valid = 0 union all
select 'REP_ALL_TASKS', count(*) from REP_ALL_TASKS where is_valid = 0 union all
select 'REP_LOAD_SESSIONS', count(*) from REP_LOAD_SESSIONS where is_valid = 0 union all
select 'REP_TASK_INST', count(*) from REP_TASK_INST where is_valid = 0
)
where anz_invalid > 0 
