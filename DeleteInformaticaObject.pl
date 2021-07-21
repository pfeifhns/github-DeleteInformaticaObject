#!/usr/bin/perl

use strict;
use DBI;

my $MasterFolder        = $ARGV[0];
my $MasterType          = $ARGV[1];
my $MasterObjectName    = $ARGV[2];
my $AutoDelete          = $ARGV[3];

my %GlobalListOfDeletion;
my %GlobalListOfDependencies;

my $lda_rep;

my $GlobalTargetDir = "/var/dwh/liefer5/ExportsInformatica";



sub GetFieldNames
{
   my ( $db, $Sql ) = @_;

   my @NewArray;

   my $sth = $db->prepare($Sql);
   $sth->execute();
   my @fields = $sth->{NAME};

   my $i=0;

   while ( length( $fields[0]->[$i] ) > 0 )
   {
      my $element = $fields[0]->[$i];
      chomp $element;
      push @NewArray, $element;
      ++$i;
   }

   return ( @NewArray );
}



sub LoginToRepository
{
     $lda_rep = DBI->connect( "dbi:Oracle:mrept_dwh" , 'pcrep_dwh_git', 'rainbow#2010' );
}


sub dbi_open
# Zweck: Cursor aus db-handle und select-statement \366ffnen und zur\374ckgeben (definierter Abbruch bei Fehler)
{
  my ($lda, $pSql) = @_;

  my $sth=$lda->prepare($pSql) || doExit (__FILE__ . " dbi_open-Abbruch", "SQL:$pSql\n\nDBIerrstr=<$DBI::errstr>");
  $sth->execute()              || doExit (__FILE__ . " dbi_open-Abbruch", "SQL:$pSql\n\nDBIerrstr=<$DBI::errstr>");
  return ($sth);
}#dbi_open

sub dbi_close
#Zweck: Handle $sth schliessen
{
  my ($sth) = @_;
  $sth->finish();
}#dbi_close


sub dbi_fetchArray
# Zweck: fetch; n\344chsten Record als Array aus $sth zurueckgeben (leeres Array am Ende)
{
  my ($sth) = @_;

  my $vArr = $sth->fetchrow_arrayref;
  doExit (__FILE__ . " dbi_fetch-Abbruch", "DBIerrstr=<$DBI::errstr>") if ($sth->err );
  return () if (not $vArr);
  return (@$vArr);
}#dbi_fetchArray

sub dbi_fetchHash
# Zweck: fetch; n\344chsten Record als Hash aus $sth zurueckgeben (leerer Hash am Ende)
{
  my ($sth) = @_;
  my $vHashRef = $sth->fetchrow_hashref;
  doExit (__FILE__ . " dbi_fetch-Abbruch", "DBIerrstr=<$DBI::errstr>") if ($sth->err );
  return ()   if (not $vHashRef);
  return (%$vHashRef);
}#dbi_fetchHash



sub getQueryResult
# Zweck: Ergebnis einer SqL-Abfrage als Array of hashes zur\374ckgeben, mit {Spaltename}=Spaltenwert
{
  my ($lda, $pSql) = @_;

  my @vResult;                            # ReturnWert

  my $csr = $lda->prepare($pSql);

  my @vArray;
  my @vTitles = GetFieldNames( $lda, $pSql );

 $csr->execute();
 while (@vArray = dbi_fetchArray($csr))
   {
    my %vHash;                              # Array-Hash
    for (my $x = 0; $vTitles[$x]; $x++) {
      $vHash{$vTitles[$x]} = $vArray[$x];
    } #for

    push (@vResult,\%vHash);
  } #while

  dbi_close ($csr);
  return (@vResult);
} #getqueryResult


sub ConnectToRepository
{
   if ( $ENV{HVSERVICE} eq "etldevsrv" )
   {
      my $db_prod      = "MREPT_DWH";
      my $db_prod_user = "PCREP_DWH_TEST";
      my $db_prod_pw   = "wobniar#2010";

      $lda_rep = DBI -> connect("dbi:Oracle:$db_prod", $db_prod_user, $db_prod_pw, {AutoCommit => 0}) ;
   }

   if ( $ENV{HVSERVICE} eq "etlgitsrv" )
   {
      my $db_prod      = "MREPT_DWH";
      my $db_prod_user = "PCREP_DWH_GIT";
      my $db_prod_pw   = "rainbow#2010";

      $lda_rep = DBI -> connect("dbi:Oracle:$db_prod", $db_prod_user, $db_prod_pw, {AutoCommit => 0}) ;
   }

   if ( $ENV{HVSERVICE} eq "etlprodsrv" )
   {
      my $db_prod      = "MREPP_DWH";
      my $db_prod_user = "PCREP_DWH_PROD";
      my $db_prod_pw   = "wobniar#2010";

      $lda_rep = DBI -> connect("dbi:Oracle:$db_prod", $db_prod_user, $db_prod_pw, {AutoCommit => 0}) ;
   }
}



sub GetParentsOfWorkflow
{
   my ( $Folder, $WorkflowName ) = @_;

   # -------------------------------------------------------
   #
   # Die Funktion prueft nach, ob $Folder->$WorkflowName
   # als wrapper-Aufruf vorkommt.
   #
   # Falls NEIN, wird eine 0 zurueckgegeben, ansonsten
   # eine Zahl groesser gleich 1
   #
   # -------------------------------------------------------

   my $SQL = "
      SELECT DISTINCT T.SUBJECT_ID, F.SUBJECT_AREA AS FOLDER_NAME,
          W.TASK_NAME AS WORKFLOW_NAME, T.TASK_NAME AS CMD_TASK_NAME,
          CMD.PM_VALUE AS CMD_NAME, CMD.EXEC_ORDER,
          CMD.VAL_NAME AS CMD_NUMBER, T.TASK_ID, T.TASK_TYPE,
          T.RU_PARENT_ID
      FROM OPB_TASK_VAL_LIST CMD, OPB_TASK T, OPB_TASK W, REP_SUBJECT F
      WHERE T.TASK_ID = CMD.TASK_ID
        AND T.SUBJECT_ID = F.SUBJECT_ID
        AND T.TASK_TYPE = 58
        AND T.RU_PARENT_ID = W.TASK_ID
        and upper( CMD.PM_VALUE ) like upper( '%$Folder%$WorkflowName%' )
      ORDER BY F.SUBJECT_AREA, W.TASK_NAME, T.TASK_NAME, CMD.EXEC_ORDER   
   ";

   my @ResultSet = getQueryResult( $lda_rep, $SQL );

   my $Stop=1;
   
   return( @ResultSet );
}


sub GetChildren
{
    my ( $Folder, $Type, $ObjectName ) = @_;

    ## Die Funktion ermittelt alle CHILDS und gibt sowohl die Anzahl der Childs als auch die Liste der Childs zurueck
    ##
    ## VORSICHT:
    ## ein Workflow kann nicht von einem Workflow abhaengig sein, das gleiche gilt fuer Workletts, Mappings und Mapplets.
    ## Sourcen, Targets und Transformations koennen sehr wohl abhaengig sein ( Shortcuts ).
    ## Deshalb wird bei der Ausgabe der Abhaengigkeitsliste je nach Typ ( workflow, worklet, mappin und mapplet ) diejenigen Zeilen entfernt.

    my $AdditionalGrepCmd = "";

#    if ( ( $Type eq 'workflow') || ( $Type eq 'mapping' )|| ( $Type eq 'worklet' )|| ( $Type eq 'maplett' ) || ( $Folder eq 'TABELLENDEFINITIONEN' ))
    {
       $AdditionalGrepCmd = " | grep -v \"$Type\" | grep -v \"non-reusable\"";
    }

    my $Cmd = "pmrep listobjectdependencies -n $ObjectName -o $Type -f $Folder -b -y -c ';' -p children | grep -e \"source\" -e \"target\" -e \"mapping\" -e \"worklet;reusable\" -e \";reusable\" $AdditionalGrepCmd";
    my @ListOfChildren = `$Cmd`;

    foreach my $CompleteObject ( @ListOfChildren )
    {
       my @SplitArray = split ';', $CompleteObject;

      my $Folder    = $SplitArray[1];
      my $Typ       = $SplitArray[2];
      my $Prefix = 0;
 
      if ( $Typ eq 'workflow' )
        {
           $Prefix=1;
        } 
        elsif ( $Typ eq 'session' )
        {
           $Prefix = 2;
        }
        elsif ( $Typ eq 'worklet' )
        {
           $Prefix=3;
        }
        elsif ( $Typ eq 'mapping' )
        {
           $Prefix=4;
        }
        elsif ( $Typ eq 'mapplet' )
        {
           $Prefix=5;
        }
        else
        {
           $Prefix =6;
        }

        if ( $Folder eq 'TABELLENDEFINITIONEN' )
        {
          $Prefix = 7;
        }

        $GlobalListOfDependencies{ "$Prefix;$CompleteObject" } = 1;
    }

    return ( $#ListOfChildren, @ListOfChildren );
}


sub GetParents
{
    my ( $Folder, $Type, $ObjectName ) = @_;

    ## Die Funktion ermittelt alle PARETNS und gibt sowohl die Anzlh der Parents als auch die Liste der Parents zurueck

    my $Cmd = "pmrep listobjectdependencies -n $ObjectName -o $Type -f $Folder -b -y -c ';' -p parents | grep -e \"workflow\" -e \"session\" -e \"worklet\" -e \"mapping\" -e \"mapplet\" -e \"source\" -e \"target\" | grep -v \";$ObjectName;\"";;
    my @List = `$Cmd`;
    return ( $#List, @List );
}


sub GetParentsUnfiltered
{
    my ( $Folder, $Type, $ObjectName ) = @_;

    ## Die Funktion ermittelt alle PARETNS und gibt sowohl die Anzlh der Parents als auch die Liste der Parents zurueck

    my $Cmd = "pmrep listobjectdependencies -n $ObjectName -o $Type -f $Folder -b -y -c ';' -p parents | grep -e \"workflow\" -e \"session\" -e \"worklet\" -e \"mapping\" -e \"mapplet\" -e \"source\" -e \"target\" ";;
    my @List = `$Cmd`;
    return ( $#List, @List );
}

sub DeleteObject
{
    my ( $Folder, $ObjectName, $Type, $TargetDir ) = @_;

    if ( $Type ne "source" && $Type ne "target" && $Type ne "session" && $Type ne "mapplet" && $Type ne "mapping" && $Type ne "workflow"  && $Type ne "worklett" )
    {
       return;
    }

    print "\n\nLoeschung von $Type $Folder.$ObjectName\n\n";

    # Vor dem Loeschen des Objektes wird nochmals geprueft, ob das Objekt wirklich keine Parents hat.
    # Dazu wird zunaechst die Funktion GetPArents genutzt. Wenn diese zurueckgibt, dass es 0 Parents gibt,
    # dann wird nochmal pmrep ListObjectDependencies aufgerufen und dies gesamte Liste angezeigt.

    my $NumOfUnfilteredParents;
    my @ArrayOfUnfilteredParents;

    my ( $NumOfParents, @ArrayOfParents )= GetParents( $Folder, $Type, $ObjectName );

    foreach my $Entry ( @ArrayOfParents )
    {
       print "$Type $Folder.$ObjectName ist abhaengig von: $Entry\n";
    }

    if ( $#ArrayOfParents == -1 )
    {
       print "$Type $Folder.$ObjectName hat offenbar keine Parents mehr und kann daher geloescht werden.\n" ;

       my $line;

       if ( $AutoDelete ne "AutoDelete" )
       { 
           print "Druecke \"y <ENTER>\" um das Objekt zu loeschen.\n";
           $line = readline(STDIN);
           chomp $line;
       }
       else
       {
           $line = 'y';
       }

       if ( $line eq 'y' )
       {
            print "Wird jetzt geloescht.\n";

           if ( !ExportObject( $Folder, $ObjectName, $Type, $GlobalTargetDir ) )
           {

              my $Cmd = `pmrep DeleteObject  -n $ObjectName -o $Type -f $Folder`;
              if ( $Cmd =~ m/failed/i )
              {
                  ErrorMessage("Das Loeschen von $Folder.$Type.$ObjectName ist fehlgeschlagen. Abbruch.\n");
                  exit;
              }
              return( 0 );
           }
      }
   }
}



sub ExportObject
{
    my ( $Folder, $ObjectName, $Type, $TargetDir ) = @_;

    my $Date = `date +%Y%m%d%H%M`;
    chomp $Date;

    my $Cmd = `pmrep ObjectExport  -n $ObjectName -o $Type -f $Folder -b -s -r -u $TargetDir/$Folder.$Type.$ObjectName.$Date`;

    if ( $Cmd !~ m/ObjectExport completed successfully/ )
    {
        ErrorMessage("Export von $Folder.$Type.$ObjectName in das Verzeichnis $TargetDir ist fehlgeschlagen. Informatica-Objekt sowie $TargetDir ueberpruefen.\n");
        exit;
    }
    return( 0 );
}


sub ErrorMessage
{
   my ( $Msg ) = @_;

   chomp $Msg;
   print "$Msg\n";
}


sub AddToListOfDeletion
{
   my ( $Folder, $Type, $ObjectName ) = @_;

   my $Key = lc $Folder . ";" . lc $Type . ";" . lc $ObjectName;
   $GlobalListOfDeletion{ $Key } = 1; 
}

sub RecursionOfChildren
{
    my ( $Folder, $Type, $ObjectName, $Level ) = @_;
    my ( $NumOfDependencies, @ListOfDependencies ) = GetChildren( $Folder, $Type, $ObjectName );

    my $Blanks;

    for ( my $i; $i < $Level; $i++ )
    {
       $Blanks = '.' . $Blanks;
    }

    ErrorMessage( $Blanks . "$Folder $Type $ObjectName (NumOfDep: $NumOfDependencies)\n" );

    foreach my $Entry ( @ListOfDependencies )
    {
        my @SplitArray = split ';', $Entry;
        my $l_Folder = $SplitArray[1];
        my $l_Type   = $SplitArray[2];

        my $l_ObName;
        if ( $SplitArray[3] eq "reusable" )
        {
           $l_ObName = $SplitArray[4];
        }
        else
        {
           $l_ObName = $SplitArray[3];
        }

        my ( $NumOfDep, @ListOfDep ) = GetChildren ( $l_Folder, $l_Type, $l_ObName );

        if ( $NumOfDep == 0 )
        {
           AddToListOfDeletion( $l_Folder, $l_Type, $l_ObName );
           #RecursionOfChildren( $l_Folder, $l_Type, $l_ObName, $Level+10 );
        }  

        RecursionOfChildren( $l_Folder, $l_Type, $l_ObName, $Level+10 );

    }
}



sub DeleteAllPossibleObjects
{
   foreach my $Key ( sort keys %GlobalListOfDependencies )
   {
      # bei einigen Informatica-Objekten steht "reusable" mit im Key. Das muss raus!
      $Key =~ s/non-reusable;//g;
      $Key =~ s/reusable;//g;

      my @Arr = split ';', $Key;
      my $Folder = $Arr[2];
      my $Typ    = $Arr[3];
      my $Object = $Arr[4];
      DeleteObject( $Folder, $Object, $Typ );
   }
}



sub PrintGlobalDependencies
{
   foreach my $Key ( sort keys %GlobalListOfDependencies )
   {
      ErrorMessage ( "Sortierte Abhaengigkeiten: $Key" );
   }
}

sub GetUnusedObjects
{

   foreach my $Key ( sort keys %GlobalListOfDependencies )
   {

      # gehe durch die ganze Liste der Children durch

      my @SplitArray = split ';', $Key;

      my $Folder     = $SplitArray[2];
      my $Type       = $SplitArray[3];
      my $ObjectName ;

      if ( $Type eq 'reusable' )
      {
         $ObjectName = $SplitArray[5];
      }
      else
      {
         $ObjectName = $SplitArray[4];
      }


      # ermittle nun die Parents

      my ( $NumOfParents, @ArrayOfParents )= GetParents( $Folder, $Type, $ObjectName );

      # convert arr to hash
        
      my %ParentHash;
      foreach my $Element ( @ArrayOfParents )
      {
          $ParentHash{ $Element } = 1;
      }

      foreach my $Object ( @ArrayOfParents )
      { 
          foreach my $DeleteObjectName ( keys %GlobalListOfDeletion )
          {
             my @ParentSplitArray = split ';', $Object;

             my $ParentFolder    = $ParentSplitArray[1];          
             my $ParentType      = $ParentSplitArray[2];          
             my $ParentObjectName;

             if ( $ParentSplitArray[3] eq 'reusable' )
             {
                 $ParentObjectName = $ParentSplitArray[4];
             }
             else  
             {
                 $ParentObjectName = $ParentSplitArray[3];
             }

             if ( lc "$ParentFolder;$ParentType;$ParentObjectName" eq lc $DeleteObjectName )
             {
                   delete $ParentHash{ $DeleteObjectName };
             }
          }
      }

      # nachdem wir diejenigen Liste aus der Parentliste herausgeworfen haben, die eh zu loeschen sind, pruefe, was jezt noch uebrig bleibt.
                
      # Falls der Hash jetzt leer ist, gibt es keinerlei Abhaengigkeiten zu anderen Informatica-Objekten. Trage daher das Objekt in die
      # Liste der zu loeschenden Elemente ein:

      my $AnzahlParentHash = scalar keys %ParentHash;

      if ( $AnzahlParentHash == 0 )
      {
         $GlobalListOfDeletion{"$Folder;$Type;$ObjectName" } = 1;
      } 

 
   }
}




# ---------------------------------------------------------------------------------
#
# M A I N
#
# ---------------------------------------------------------------------------------


# #################################################################################
#
# Pruefe, ob Parameter gesetzt sind
#
# ---------------------------------------------------------------------------------

if ( $MasterType ne 'workflow' && $MasterType ne 'session' && $MasterType ne 'worklet' && $MasterType ne 'mapping' && $MasterType ne 'mapplet' && $MasterType ne 'source' && $MasterType ne 'target' )
{
    print "Aufruf: perl \$PMExtProcDir/DeleteInformaticaObject.pl Folder Type ObjectName\n";
    print "        Parameter \"Type\" muss ein Wert aus dieser Liste sein: workflow / session / worklet / mapping / mapplet / source / target\n";
    exit;
}

#mil $CmdRep="sh \$PMExtProcDir/login_pmrep.sh";
#my $RetVal = `$CmdRep`;
#print "Login zu Informatica Repository ueber pmrep\n$RetVal\n";    




# 1.Schritt
#
# Fuer den Fall, dass ein Workflow geloescht werden soll, muss zuvor geprueft werden, ob der Workflow ueber 
# der dwh_wrapper aufgerufen wird. Falls ja, wird die Verarbeitung abgebrochen, ansonsten weitergemacht

   # Login zum Repository

   if ( lc $MasterType =~ m/workflow/ )
   {
      ConnectToRepository;
      my @ListOfParent = GetParentsOfWorkflow( $MasterFolder, $MasterObjectName );

      if ( $#ListOfParent >= 0 )
      {
         # Zeige die Liste der Parents an:
         print "Der Workflow $MasterFolder.$MasterObjectName wird ueber den dwh_wrapper in den folgenden Workflows aufgerufen:\n";

         for my $i ( 0 .. $#ListOfParent )
         {
            print "$ListOfParent[$i]{'FOLDER_NAME'}.$ListOfParent[$i]{'WORKFLOW_NAME'} Command $ListOfParent[$i]{'CMD_TASK_NAME'}\n";
         }

         print "Der Loeschvorgang wird daher komplett abgebrochen.\n";
         exit;
      }

   }


# 1.Schritt
#
# Pruefe nach, dass es zum Hauptobjekt keine Parents mehr gibt. Wenn es Parents gibt, dann darf NICHTS geloescht werden

my ( $NumOfMasterParents, @MasterListOfParents ) = GetParents( $MasterFolder, $MasterType, $MasterObjectName );

if ( $#MasterListOfParents >= 0 )
{
   ErrorMessage( "$MasterFolder.$MasterType.$MasterObjectName hat noch PARENTS, es darf daher NICHT geloescht werden." );
   
   foreach my $Entry( @MasterListOfParents )
   {
     chomp $Entry;
     ErrorMessage( "     Parent: $Entry" );
   }

   exit;
}



# 2. Schritt
#
# Wenn das Programm bis hierher kommt, dann gab es fuer das Hauptobjekt keine Parents.
#

# 2.1 : fuege das masterobjekt in die Liste der zu loeschenden Objekte ein:

#AddToListOfDeletion( $MasterFolder, $MasterType, $MasterObjectName );

print "Es werden jetzt die Abhaengigkeiten ermittelt und diese anschliessend in die richtie Reihenfolge zum Loeschen gebracht.\n";
RecursionOfChildren( $MasterFolder, $MasterType, $MasterObjectName, 1 ); 

print "\nReihenfolge zum Loeschen:\n";
PrintGlobalDependencies;

# Loesche das HauptObjekt
DeleteObject( $MasterFolder, $MasterObjectName, $MasterType  );

DeleteAllPossibleObjects;

#GetUnusedObjects;

my $StopHere = 1;


