# See bottom of file for license and copyright information

=begin TML

---+ Role Foswiki::Aux::Callbacks

*Experimental*

_This documentation is a draft as callbacks are not finalized and are changing_

Support of callbacks for classes which may need them. Might be replaced by
future new plugins code or become a part of it.

A callback name is a composition of namespace and it's short name combined by
'::'. By default namespace is equal to the name of module which is registering
the callback. For example, =Foswiki::App= is registering =postConfig= callback.
In this case it could be referenced by the name =Foswiki::App::postConfig=.
Whenever namespace could be guessed callback can be referenced by it's short
name. So, when =Foswiki::App= is calling =postConfig= it can do it by simply
issuing the following call:

<verbatim>
$this->callback('postConfig', $params);
</verbatim>

and the namespace will be guessed by the =callback= method using caller's
package name.

Similarly to this a client registering callback might use the shortname but it
will work only when the name is used only in one namespace. Otherwise an
exception (ASSERT) with error will be raised.

Callback is a coderef (a sub) which gets called at certain moments of a class
life cycle. A callback sub is supplied with the following arguments:

   1 Reference to the object which is calling the callback.
   1 A list of key/value pairs where the following keys are defined:
      * =data= User data if supplied by the object which has registered this callback. Data format determined by the registering object.
      * =params= Parameteres supplied by the calling object. Data format defined by the object and must be documented.
      
A named callback may have more than one handler. In this case all handlers are
executed in the order they were registerd. No return values are respecred. If a
handler wants to be the last it must raise =Foswiki::Exception::Ext::Last=
exception. If set, exception's =rc= attribute contains what is returned by
=callback()= method then.

If a callback handler raises any other exception besides of
=Foswiki::Exception::Ext::*= then that exception is rethrown further up the call
stack.

Example callback handler may look like:

<verbatim>
sub cbHandler {
    my $obj = shift;
    my %args = @_;
    
    my $this = $args{data}{this};
    
    my $rc;
    
    ... # Do something.
    
    if ($errorHappened) {
        Foswiki::Exception::Fatal->throw( text => "That's bad!" );
    }
    
    # Suppose that $rc is set when the 
    if (defined $rc) {
        Foswiki::Exception::Ext::Last->throw( rc => $rc );
    }
}
</verbatim>

=cut

package Foswiki::Aux::Callbacks;
use v5.14;

use Assert;
use Try::Tiny;
use Scalar::Util qw(weaken);

# Hash of registered callback names in a form of:
# $_registeredNames{'Foswiki::NameSpace'}{callbackName} = 1;
my %_registeredCBNames;
my %_cbNameIndex;

use Moo::Role;

around BUILD => sub {
    my $orig = shift;
    my $this = shift;

    $this->callbacksInit;
    return $orig->( $this, @_ );
};

before DEMOLISH => sub {
    my $this = shift;

    #$this->_traceMsg("Callbacks DEMOLISH");

    # Cleanup all callbacks registed by this object.
    my $appHeap = $this->_getApp->heap;

    foreach my $cbName ( keys %{ $appHeap->{_aux_registered_callbacks} } ) {
        $this->deregisterCallback($cbName);
    }
};

# Splits full callback name into namespace and short name.
sub _splitCBName {
    my $this = shift;

    $_[0] =~ /^(.*)::([^:]+)$/;
    return ( $1, $2 );
}

# Returns currently active Foswiki::App object.
sub _getApp {
    my $this = shift;

    return (
        $this->isa('Foswiki::App') ? $this
        : (
            $this->does('Foswiki::AppObject') ? $this->app
            : (      $this->does('Foswiki::Aux::_ExtensibleRole')
                  && $this->_has__appObj ? $this->__appObj : $Foswiki::app )
        )
    );
}

# Normilizes callback name to it's full form of 'namespace::cbName'. If cbName
# is short (i.e. doesn't contain ::) then namespace if fetched from index. If
# more than one namespace registered a callback with the same name then assert
# exception is raised.
sub _guessCallbackName {
    my $this = shift;
    my ($name) = @_;

    return $name if $name =~ /::/;

    my @ns = @{ $_cbNameIndex{$name} };

    return $name unless @ns;

    ASSERT(
        @ns == 1,
        "Ambiguous callback name `$name': registered by "
          . scalar(@ns)
          . " namespace(s)"
    );

    return $ns[0] . '::' . $name;
}

=begin TML

---++ ObjectMethod callbacksInit()

This method is virtual. Can be overriden by classes to which this role has been
applied. It is guaranteed to be called before any actual callback is called by
an object of the class.

=cut

sub callbacksInit {
}

=begin TML

---++ ObjectMethod registerCallback($name, $fn, $userData)

Adds coderef =$fn= to the list of registered handlers of callback =$name=.

Callback =$name= must be supported by the class.

=cut

sub registerCallback {
    my $this = shift;
    my ( $name, $fn, $userData ) = @_;

    ASSERT( ref($fn) eq 'CODE',
        "callback must be a coderef in a call to registerCallback method" );

    $name = $this->_guessCallbackName($name);

    ASSERT( $_registeredCBNames{$name}, "unknown callback '$name'" );

    my $cbInfo = {
        code => $fn,
        data => $userData,
        obj  => $this->__id,
    };

    push @{ $this->_getApp->heap->{_aux_registered_callbacks}{$name} }, $cbInfo;
}

=begin TML

---+++ ObjectMethod deregisterCallback( $name [, $fn] )

Deregisters callbacks registered by the object and defined by =$name=. If =$fn=
is not defined then all registrations for callback =$name= are dropped.
Otherwise it's only those pointing at coderef in =$fn= are affected. 

=cut

sub deregisterCallback {
    my $this = shift;
    my ( $name, $fn ) = @_;

    ASSERT( ref($fn) eq 'CODE',
        "callback must be a coderef in a call to deregisterCallback method" )
      if defined $fn;

    $name = $this->_guessCallbackName($name);

    ASSERT( $_registeredCBNames{$name}, "unknown callback '$name'" );

    my $objId   = $this->__id;
    my $appHeap = $this->_getApp->heap;
    my $oldList = $appHeap->{_aux_registered_callbacks}{$name};
    my $newList = [];

    #$this->_traceMsg("Deregistering callback `$name' for object $objId");

    foreach my $cbInfo (@$oldList) {
        push @$newList, $cbInfo
          unless ( $cbInfo->{obj} eq $objId )
          && ( !defined($fn) || $cbInfo->{code} == $fn );
    }

    $appHeap->{_aux_registered_callbacks}{$name} = $newList;
}

=begin TML

---++ ObjectMethod callback($name, \%params)

=cut

sub callback {
    my $this = shift;
    my ( $name, $params ) = @_;

    $name = caller . "::$name" unless $name =~ /::/;

    ASSERT( $_registeredCBNames{$name}, "unknown callback '$name'" );

    my $lastException;
    my $cbList = $this->_getApp->heap->{_aux_registered_callbacks}{$name};

    return unless $cbList;

    my $restart;
    do {
        $restart = 0;
        my $lastIteration = 0;
        my ( $cbIdx, $cbInfo );
        values @$cbList;
        while (!$lastIteration
            && !$lastException
            && ( ( $cbIdx, $cbInfo ) = each @$cbList ) )
        {
            try {
                $cbInfo->{code}
                  ->( $this, data => $cbInfo->{data}, params => $params, );
            }
            catch {
                my $e = Foswiki::Exception::Fatal->transmute( $_, 0 );
                if ( $e->isa('Foswiki::Exception::Ext::Flow') ) {
                    if ( $e->isa('Foswiki::Exception::Ext::Last') ) {
                        $lastException = $e;
                    }
                    elsif ( $e->isa('Foswiki::Exception::Ext::Restart') ) {
                        $params->{execRestarted} = {
                            code => $cbInfo->{code},
                            data => $cbInfo->{data},
                        };
                        $lastIteration = $restart = 1;
                    }
                    else {
                        Foswiki::Exception::Fatal->throw(
                                text => "Unknown callback exception "
                              . ref($e)
                              . "; the exception data is following:\n"
                              . $e->stringify, );
                    }
                }
                else {
                    $e->rethrow;
                }
            };
        }
    } while ($restart);

    if ( $lastException && $lastException->has_rc ) {
        return $lastException->rc;
    }

    return;
}

=begin TML

---++ StaticMethod registerCallbackNames($namespace, @cbNames)

Registers callback names on name space =$namespace=. Called by =Foswiki::Class=
exported =callback_names=.

=cut

sub registerCallbackNames {
    my $namespace = shift;
    $namespace = ref($namespace) || $namespace;

    foreach (@_) {
        my $cbName = "${namespace}::$_" unless /::/;
        $_registeredCBNames{$cbName} = 1;
        push @{ $_cbNameIndex{$_} }, $namespace;
    }

}

1;
__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2016 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.