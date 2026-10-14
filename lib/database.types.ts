// مولَّد من Supabase (generate_typescript_types) — لا تعدّله يدويًا.
export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.18"
  }
  public: {
    Tables: {
      accounts: {
        Row: {
          code: string
          created_at: string
          id: number
          is_active: boolean
          is_postable: boolean
          is_treasury: boolean
          name: string
          parent_id: number | null
          type: string
        }
        Insert: {
          code: string
          created_at?: string
          id?: never
          is_active?: boolean
          is_postable?: boolean
          is_treasury?: boolean
          name: string
          parent_id?: number | null
          type: string
        }
        Update: {
          code?: string
          created_at?: string
          id?: never
          is_active?: boolean
          is_postable?: boolean
          is_treasury?: boolean
          name?: string
          parent_id?: number | null
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: "accounts_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      doc_counters: {
        Row: {
          kind: string
          last_no: number
        }
        Insert: {
          kind: string
          last_no?: number
        }
        Update: {
          kind?: string
          last_no?: number
        }
        Relationships: []
      }
      journal_entries: {
        Row: {
          created_at: string
          created_by: string
          description: string
          entry_date: string
          entry_no: number
          id: number
          reverses_entry_id: number | null
          source_id: number | null
          source_type: string
        }
        Insert: {
          created_at?: string
          created_by: string
          description: string
          entry_date: string
          entry_no: number
          id?: never
          reverses_entry_id?: number | null
          source_id?: number | null
          source_type: string
        }
        Update: {
          created_at?: string
          created_by?: string
          description?: string
          entry_date?: string
          entry_no?: number
          id?: never
          reverses_entry_id?: number | null
          source_id?: number | null
          source_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "journal_entries_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entries_reverses_entry_id_fkey"
            columns: ["reverses_entry_id"]
            isOneToOne: true
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      journal_lines: {
        Row: {
          account_id: number
          credit: number
          debit: number
          description: string | null
          entry_id: number
          id: number
        }
        Insert: {
          account_id: number
          credit?: number
          debit?: number
          description?: string | null
          entry_id: number
          id?: never
        }
        Update: {
          account_id?: number
          credit?: number
          debit?: number
          description?: string | null
          entry_id?: number
          id?: never
        }
        Relationships: [
          {
            foreignKeyName: "journal_lines_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_lines_entry_id_fkey"
            columns: ["entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          created_at: string
          email: string | null
          full_name: string | null
          id: string
          role: string
        }
        Insert: {
          created_at?: string
          email?: string | null
          full_name?: string | null
          id: string
          role?: string
        }
        Update: {
          created_at?: string
          email?: string | null
          full_name?: string | null
          id?: string
          role?: string
        }
        Relationships: []
      }
      settings: {
        Row: {
          company_address: string | null
          company_name: string
          company_phone: string | null
          currency_name: string
          currency_symbol: string
          id: number
          lock_date: string | null
        }
        Insert: {
          company_address?: string | null
          company_name: string
          company_phone?: string | null
          currency_name?: string
          currency_symbol?: string
          id?: number
          lock_date?: string | null
        }
        Update: {
          company_address?: string | null
          company_name?: string
          company_phone?: string | null
          currency_name?: string
          currency_symbol?: string
          id?: number
          lock_date?: string | null
        }
        Relationships: []
      }
      system_accounts: {
        Row: {
          account_id: number
          key: string
        }
        Insert: {
          account_id: number
          key: string
        }
        Update: {
          account_id?: number
          key?: string
        }
        Relationships: [
          {
            foreignKeyName: "system_accounts_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      account_statement: {
        Args: { p_account_id: number; p_from?: string; p_to?: string }
        Returns: {
          balance: string
          credit: string
          debit: string
          description: string
          entry_date: string
          entry_id: number
          entry_no: number
          source_type: string
        }[]
      }
      cancel_journal_entry: { Args: { p_entry_id: number }; Returns: number }
      journal_entry_list: {
        Args: { p_from?: string; p_search?: string; p_to?: string }
        Returns: {
          description: string
          entry_date: string
          entry_no: number
          id: number
          reversed_by_entry_id: number
          reverses_entry_id: number
          source_type: string
          total: string
        }[]
      }
      post_journal_entry: {
        Args: {
          p_description: string
          p_entry_date: string
          p_lines: Json
          p_source_type: string
        }
        Returns: number
      }
      post_opening_balances: {
        Args: {
          p_difference_to_capital?: boolean
          p_entry_date: string
          p_lines: Json
        }
        Returns: number
      }
      trial_balance: {
        Args: { p_as_of?: string }
        Returns: {
          account_id: number
          code: string
          credit: string
          debit: string
          name: string
          type: string
        }[]
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never
