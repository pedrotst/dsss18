Require Import String.

From DeepWeb.Proofs.Vst
     Require Import VstInit VstLib Connection Store.

Require Import DeepWeb.Spec.ITreeSpec.

Open Scope logic.
Open Scope list.

Set Bullet Behavior "Strict Subproofs".

(***************************** populate_response ******************************)

Definition populate_response_spec :=
  DECLARE _populate_response
  WITH conn : connection,
       fd : sockfd,
       last_msg : string,
       conn_ptr : val,
       last_msg_store_ptr : val
  PRE [ _conn OF tptr (Tstruct _connection noattr),
        _last_msg_store OF tptr (Tstruct _store noattr)
      ]
    PROP ( )
    LOCAL ( temp _conn conn_ptr ; 
            temp _last_msg_store last_msg_store_ptr )
    SEP (
      (* data_at Ews (Tstruct _connection noattr) (gv _last_conn); *)
        list_cell LS Tsh (rep_connection conn fd) conn_ptr ;
        field_at Tsh (Tstruct _store noattr) [] (rep_store last_msg)
                 last_msg_store_ptr )
  POST [ tint ]
    EX r : Z, 
    EX conn' : connection,
    EX new_msg : string,
    PROP ( r = 1 ;
           (* r = 0 -> conn' = conn /\ new_msg = last_msg ; *)
           r = 1 -> conn' = upd_conn_response_bytes_sent
                             (upd_conn_response conn last_msg)
                             0 /\
                   new_msg = conn_request conn
         )
    LOCAL ( temp ret_temp (Vint (Int.repr r)) )
    SEP ( list_cell LS Tsh (rep_connection conn' fd) conn_ptr;
          field_at Tsh (Tstruct _store noattr) [] (rep_store new_msg)
                   last_msg_store_ptr
        ).
